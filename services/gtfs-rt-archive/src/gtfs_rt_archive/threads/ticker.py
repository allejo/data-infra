import time
import threading

class Ticker(threading.Thread):
    def __init__(self, logger, evtbus, tickint):

        super().__init__()

        self.logger = logger
        self.evtbus = evtbus
        self.tickint = tickint
        self.name = "ticker"
        self.tickid = 0

    def tick(self):
        evt = ("tick", self.tickid, int(time.time()))
        self.logger.notice("{}: emit: {}".format(self.name, evt))
        self.evtbus.emit(evt)
        self.tickid += 1

    def run(self):

        self.tickid = 0
        self.tick()

        while time.sleep(self.tickint) is None:
            self.tick()
