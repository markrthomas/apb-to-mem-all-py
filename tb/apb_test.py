"""Tests and the cocotb entry points that launch the pyuvm testbench."""

import cocotb

from pyuvm import ConfigDB, uvm_root, uvm_test

from apb_bfm import ApbBfm
from apb_components import ApbEnv
from apb_seq import ApbRandomSeq, ApbWalkingSeq, ApbWriteReadSeq


class BaseTest(uvm_test):
    """Builds the env and handles clock + reset via the BFM."""

    seq_cls = ApbWriteReadSeq

    def build_phase(self):
        self.env = ApbEnv("env", self)

    async def run_phase(self):
        self.raise_objection()
        bfm = ApbBfm()
        await bfm.start_clock()
        await bfm.reset()

        seqr = ConfigDB().get(self, "", "SEQR")
        seq = self.seq_cls()
        await seq.start(seqr)
        self.drop_objection()


class WriteReadTest(BaseTest):
    seq_cls = ApbWriteReadSeq


class RandomTest(BaseTest):
    seq_cls = ApbRandomSeq


class WalkingTest(BaseTest):
    seq_cls = ApbWalkingSeq


# -- cocotb entry points ------------------------------------------------------
# TESTCASE (from the Makefile) selects which one runs; default runs all.

@cocotb.test()
async def write_read_test(_dut):
    await uvm_root().run_test("WriteReadTest")


@cocotb.test()
async def random_test(_dut):
    await uvm_root().run_test("RandomTest")


@cocotb.test()
async def walking_test(_dut):
    await uvm_root().run_test("WalkingTest")
