#!/usr/bin/env python
import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import Any, Dict, List, Optional

import gcsfs  # type: ignore
import pendulum
import sentry_sdk
import typer
from dbt_artifacts import (
    DbtResourceType,
    Manifest,
    Node,
    RunResult,
    RunResults,
    RunResultStatus,
)

CALITP_BUCKET__DBT_ARTIFACTS = os.getenv("CALITP_BUCKET__DBT_ARTIFACTS")

artifacts = map(
    Path, ["index.html", "catalog.json", "manifest.json", "run_results.json"]
)

sentry_sdk.init(environment=os.environ["AIRFLOW_ENV"])

app = typer.Typer(pretty_exceptions_enable=False)


class DbtException(Exception):
    pass


class DbtSeedError(Exception):
    pass


class DbtModelError(Exception):
    pass


class DbtTestError(Exception):
    pass


class DbtTestFail(Exception):
    pass


class DbtTestWarn(Exception):
    pass


def get_failure_context(failure: RunResult, node: Node) -> Dict[str, Any]:
    context: Dict[str, Any] = {
        "unique_id": failure.unique_id,
    }
    if failure.unique_id.startswith("test"):
        if node.depends_on:
            context["models"] = node.depends_on.nodes
    return context


def report_failures_to_sentry(
    run_results: RunResults,
    manifest: Manifest,
    verbose: bool = False,
) -> None:
    failures = [
        result
        for result in run_results.results
        if result.status
        in (
            RunResultStatus.error,
            RunResultStatus.fail,
            RunResultStatus.warn,
        )
    ]
    for failure in failures:
        node = manifest.nodes[failure.unique_id]
        fingerprint = [failure.status, failure.unique_id]
        # this is awkward and manual; maybe could do dynamically
        exc_types = {
            (DbtResourceType.seed, RunResultStatus.error): DbtSeedError,
            (DbtResourceType.model, RunResultStatus.error): DbtModelError,
            (DbtResourceType.test, RunResultStatus.error): DbtTestError,
            (DbtResourceType.test, RunResultStatus.fail): DbtTestFail,
            (DbtResourceType.test, RunResultStatus.warn): DbtTestWarn,
        }
        exc_type = exc_types.get((node.resource_type, failure.status), DbtException)
        if verbose:
            typer.secho(
                f"reporting failure of {node.resource_type} with fingerprint {fingerprint}",
                fg=typer.colors.YELLOW,
            )
        with sentry_sdk.push_scope() as scope:
            scope.fingerprint = fingerprint
            scope.set_context("dbt", get_failure_context(failure, node))
            sentry_sdk.capture_exception(
                error=exc_type(f"{failure.unique_id} - {failure.message}"),
            )


@app.command()
def report_failures(
    run_results_path: Path = Path("./target/run_results.json"),
    manifest_path: Path = Path("./target/manifest.json"),
    verbose: bool = False,
):
    with open(run_results_path) as f:
        run_results = RunResults(**json.load(f))
    with open(manifest_path) as f:
        manifest = Manifest(**json.load(f))
    report_failures_to_sentry(run_results, manifest, verbose=verbose)


@app.command()
def run(
    project_dir: Path = Path(os.environ.get("DBT_PROJECT_DIR", os.getcwd())),
    profiles_dir: Path = Path(os.environ.get("DBT_PROFILES_DIR", os.getcwd())),
    target: Optional[str] = os.environ.get("DBT_TARGET"),
    dbt_seed: bool = True,
    dbt_run: bool = True,
    full_refresh: bool = False,
    dbt_test: bool = False,
    dbt_freshness: bool = False,
    dbt_docs: bool = False,
    save_artifacts: bool = False,
    deploy_docs: bool = False,
    sync_metabase: bool = False,
    select: Optional[str] = None,
    exclude: Optional[str] = None,
) -> None:
    assert (
        dbt_docs or not save_artifacts
    ), "cannot save artifacts without generating them!"
    assert (
        CALITP_BUCKET__DBT_ARTIFACTS or not save_artifacts
    ), "must specify an artifacts bucket if saving artifacts"
    assert dbt_docs or not deploy_docs, "cannot deploy docs without generating them!"

    def get_command(*args) -> List[str]:
        cmd = [
            "dbt",
            *args,
            "--project-dir",
            project_dir,
            "--profiles-dir",
            profiles_dir,
        ]

        if target:
            cmd.extend(
                [
                    "--target",
                    target,
                ]
            )
        return cmd

    results_to_check = []

    if dbt_seed:
        results_to_check.append(subprocess.run(get_command("seed")))

        with open("./target/run_results.json") as f:
            run_results = RunResults(**json.load(f))
        with open("./target/manifest.json") as f:
            manifest = Manifest(**json.load(f))

        report_failures_to_sentry(run_results, manifest)

    if dbt_run:
        args = ["run"]
        if full_refresh:
            args.append("--full-refresh")
        if select:
            args.extend(["--select", *select.split(" ")])
        if exclude:
            args.extend(["--exclude", exclude])
        results_to_check.append(subprocess.run(get_command(*args)))

        with open("./target/run_results.json") as f:
            run_results = RunResults(**json.load(f))
        with open("./target/manifest.json") as f:
            manifest = Manifest(**json.load(f))
        report_failures_to_sentry(run_results, manifest)
    else:
        typer.secho("skipping run, only compiling", fg=typer.colors.YELLOW)
        args = ["compile"]
        if full_refresh:
            args.append("--full-refresh")
        subprocess.run(get_command(*args)).check_returncode()

    if dbt_test:
        args = ["test"]
        if exclude:
            args.extend(["--exclude", exclude])
        subprocess.run(get_command(*args))

        with open("./target/run_results.json") as f:
            run_results = RunResults(**json.load(f))
        with open("./target/manifest.json") as f:
            manifest = Manifest(**json.load(f))

        report_failures_to_sentry(run_results, manifest)

    if dbt_freshness:
        results_to_check.append(
            subprocess.run(get_command("source", "snapshot-freshness"))
        )

    if dbt_docs:
        subprocess.run(get_command("docs", "generate")).check_returncode()

        os.mkdir("docs/")

        fs = gcsfs.GCSFileSystem(
            project="cal-itp-data-infra",
            token=os.getenv("BIGQUERY_KEYFILE_LOCATION"),
        )

        ts = pendulum.now()

        # TODO: we need to save run_results from the run and not the docs generate
        for artifact in artifacts:
            _from = str(project_dir / Path("target") / artifact)

            if save_artifacts:
                # Save the latest ones for easy retrieval downstream
                # but also save using the usual artifact types
                latest_to = f"{CALITP_BUCKET__DBT_ARTIFACTS}/latest/{artifact}"
                # TODO: this should use PartitionedGCSArtifact at some point
                assert CALITP_BUCKET__DBT_ARTIFACTS  # unsure why mypy wants this
                timestamped_to = "/".join(
                    [
                        CALITP_BUCKET__DBT_ARTIFACTS,
                        str(artifact),
                        f"dt={ts.to_date_string()}",
                        f"ts={ts.to_iso8601_string()}",
                        str(artifact),
                    ]
                )
                typer.echo(f"writing {_from} to {latest_to} and {timestamped_to}")
                fs.put(lpath=_from, rpath=latest_to)
                fs.put(lpath=_from, rpath=timestamped_to)
            else:
                typer.echo(f"skipping upload of {artifact}")

            # avoid copying run_results is unnecessary for the docs site
            # so just skip to avoid any potential information leakage
            if "run_results" not in str(artifact):
                shutil.copy(_from, "docs/")

        if deploy_docs:
            args = [
                "netlify",
                "deploy",
                "--dir=docs/",
            ]

            if target and target.startswith("prod"):
                args.append("--prod")

            results_to_check.append(subprocess.run(args))

    # There's a flag called --metabase_sync_skip but it doesn't seem to work as I assumed
    # so we only want to sync in production. This makes it hard to test, but we don't really
    # use the pre-prod Metabase right now; we could theoretically test with that if it
    # synced schemas created by the staging dbt target.
    if sync_metabase:
        if target and target.startswith("prod"):
            # TODO: we should be logging each misaligned model to Sentry
            subprocess.run(
                [
                    "dbt-metabase",
                    "models",
                    "--metabase_exclude_sources",
                    "--dbt_manifest_path",
                    "./target/manifest.json",
                    "--dbt_docs_url",
                    "https://dbt-docs.calitp.org",
                    "--metabase_database",
                    "Data Marts (formerly Warehouse Views)",
                    "--dbt_schema_excludes",
                    "staging",
                    "payments",
                ]
            )
        else:
            typer.secho(
                f"WARNING: running with non-prod target {target} so skipping metabase sync",
                fg=typer.colors.YELLOW,
            )

    for result in results_to_check:
        result.check_returncode()


if __name__ == "__main__":
    app()
