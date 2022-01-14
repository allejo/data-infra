from fileinput import filename
from airflow.models import BaseOperator
from airflow.utils.decorators import apply_defaults
from google.transit import gtfs_realtime_pb2
from google.protobuf import json_format
from google.protobuf.message import DecodeError
from calitp.storage import get_fs
from calitp.config import get_bucket
from collections import defaultdict
from pathlib import Path

import pandas as pd
import tempfile

# Note that all RT extraction is stored in the prod bucket, since it is very large,
# but we can still output processed results to the staging bucket
SRC_PATH = "gs://gtfs-data/rt/"
DST_PATH = "gs://gtfs-data/rt-processed/"


class RealtimeProcessor(BaseOperator):
    def __init__(
        self,
        execution_date,
        header_details,
        entity_details,
        filename_prefix,
        rt_file_substring,
        cast={},
        is_timestamp=[],
        **kwargs,
    ):
        super().__init__(**kwargs)

        self.fs = get_fs()
        self.iso_date = str(execution_date).split("T")[0]
        self.header_details = header_details
        self.entity_details = entity_details
        self.filename_prefix = filename_prefix
        self.rt_file_substring = rt_file_substring
        self.cast = cast
        self.time_float_cast = {col: "float" for col in is_timestamp}
        self.dst_path = f"{get_bucket()}/rt-processed/" + self.rt_file_substring + "/"

    def parse_pb(self, path):
        """
        Convert pb file to Python dictionary
        """

        open_with = self.fs.open
        open_func = open_with if open_with is not None else open
        feed = gtfs_realtime_pb2.FeedMessage()
        try:
            feed.ParseFromString(open_func(path, "rb").read())
            d = json_format.MessageToDict(feed)
        except DecodeError:
            d = {}
        d.update({"calitp_filepath": path})
        return d

    def pull_value(self, x, path):
        """
        Safe extraction for pulling entity values
        """
        crnt_obj = x
        for attr in path.split("."):
            try:
                crnt_obj = crnt_obj[attr]
            except KeyError:
                return None
        return crnt_obj

    def get_header_details(self, x):
        """
        Returns a dictionary of header values to be added to a dataframe
        """
        parsed_header_details = {
            col: self.pull_value(x, source)
            for col, source in self.header_details.items()
        }
        return parsed_header_details

    def rectangle_entities(self, x):
        """
        Create a dataframe from parsed pb files
        """
        header_details = self.get_header_details(x)
        entity_details = self.get_entity_details(x)
        if len(entity_details) > 0:
            rectangle = pd.DataFrame(entity_details)
            for k, v in header_details.items():
                rectangle[k] = v
            return rectangle
        else:
            return None

    def fetch_bucket_file_names(self):
        # posix_date = str(time.mktime(execution_date.timetuple()))[:6]

        # get rt files
        print("Globbing rt bucket...")
        print(SRC_PATH + self.iso_date + "*")
        rt = self.fs.glob(SRC_PATH + self.iso_date + "*")

        buckets_to_parse = len(rt)
        print("Realtime buckets to parse: {i}".format(i=buckets_to_parse))

        # organize rt files by itpId_urlNumber
        rt_files = []
        for r in rt:
            rt_files.append(self.fs.ls(r))

        entity_files = [
            item
            for sublist in rt_files
            for item in sublist
            if self.get_rt_file_substr() in item
        ]

        feed_files = defaultdict(lambda: [])

        for fname in entity_files:
            itpId, urlNumber = fname.split("/")[-3:-1]
            feed_files[(itpId, urlNumber)].append(fname)

        # Now our feed files dict has a key of itpId_urlNumber and a list of files to
        # parse
        return feed_files

    def get_google_cloud_filename(self, feed):
        itp_id_url_num = "_".join(map(str, feed))
        prefix = self.filename_prefix
        return f"{prefix}_{self.iso_date}_{itp_id_url_num}.parquet"

    def cast_entities(self, entities):
        # parse any information provided about fields that need to have dtype changed
        # e.g. timestamps are strings, and latitude may be inferred as an int.
        # note that due to a pandas bug, we first convert timestamps to
        # a float, and then to an integer (hence the separate time_float_cast check)
        # see: https://stackoverflow.com/a/60024263

        return entities.astype(self.time_float_cast).astype(self.cast)

    def get_entity_details(self, x):
        """
        Returns a list of dicts containing entity values to be added to a dataframe.
        See https://gtfs.org/reference/realtime/v2/ for list of possible
        entity values by message type.
        """
        entity = x.get("entity")
        parsed_entity_details = []
        if entity is not None:
            for e in entity:
                e_details = {
                    col: self.pull_value(e, source)
                    for col, source in self.entity_details.items()
                }
                parsed_entity_details.append(e_details)
        return parsed_entity_details

    def execute(self):
        """Process a RT feed of the given type

        Args:
            rt_type (string): One of "alerts", "trip_updates", "vehicle_positions"
            execution_date (date): The execution date being processed
        """

        # fetch files ----
        # for some reason the fs.glob command takes up a fair amount of memory here,
        # and does not seem to free it after the function returns, so we manually clear
        # its caches (at lest the ones I could find)
        feed_files = self.fetch_bucket_file_names(self.fs)
        self.fs.dircache.clear()

        # parse feeds ----
        for feed, files in feed_files.items():
            google_cloud_file_name = self.get_google_cloud_filename(feed)
            print("Creating " + google_cloud_file_name)
            print("  parsing %s files" % len(files))

            if len(files) > 0:
                # fetch and parse RT files from bucket
                with tempfile.TemporaryDirectory() as tmp_dir:
                    self.fs.get(files, tmp_dir)
                    all_files = [x for x in Path(tmp_dir).rglob("*") if not x.is_dir()]

                    parsed_entities = [self.parse_pb(fn) for fn in all_files]

                # convert protobuff objects to DataFrames
                entities_dfs = [*map(self.rectangle_entities, parsed_entities)]
                entities_dfs = [df for df in entities_dfs if df is not None]

                print("  %s entities sub dataframes created" % len(entities_dfs))
                if len(entities_dfs) > 0:
                    entities_rectangle = pd.concat(entities_dfs)
                    entities_rectangle.insert(0, "calitp_itp_id", int(feed[0]))
                    entities_rectangle.insert(1, "calitp_url_number", int(feed[1]))

                    # cast fields that may get screwed up
                    casted = self.cast_entities(entities_rectangle)

                    with tempfile.TemporaryDirectory() as tmpdirname:
                        fname = tmpdirname + "/" + "temporary" + ".parquet"
                        casted.to_parquet(fname, index=False)
                        self.fs.put(
                            fname,
                            self.get_dst_path() + google_cloud_file_name,
                        )
