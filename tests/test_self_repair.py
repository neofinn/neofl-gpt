import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'python'))

from neofl_gateway.self_repair import SelfRepairEngine


def test_self_repair_requires_approval():
    engine = SelfRepairEngine()
    proposal = engine.propose(
        target='python/demo.py',
        old_content='x = 1\n',
        new_content='x = 2\n',
        summary='Correct demo value',
        validations=['python -m py_compile python/demo.py'],
    )
    result = engine.validate(proposal, lambda p: (True, ['validator-called']))
    assert result.status == 'REVIEW_REQUIRED'
    assert result.rollback_available


def test_approved_repair_validates_and_records_memory():
    engine = SelfRepairEngine()
    proposal = engine.propose(
        target='python/demo.py',
        old_content='x = 1\n',
        new_content='x = 2\n',
        summary='Correct demo value',
        validations=['syntax', 'targeted-test'],
    )
    proposal = engine.coder.approve(proposal)
    result = engine.validate(proposal, lambda p: (True, ['syntax:ok', 'targeted-test:ok']))
    assert result.status == 'VALIDATED'
    assert engine.coder.memory.recall(target='python/demo.py')


def test_failed_validation_is_fail_closed():
    engine = SelfRepairEngine()
    proposal = engine.propose(
        target='python/demo.py',
        old_content='x = 1\n',
        new_content='x = broken\n',
        summary='Bad repair example',
        validations=['syntax'],
    )
    proposal = engine.coder.approve(proposal)
    result = engine.validate(proposal, lambda p: (False, ['syntax:failed']))
    assert result.status == 'REJECTED'
    assert result.rollback_available
