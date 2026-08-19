import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'python'))

from neofl_gateway.agent import AgentLoop, AgentRequest


def test_agent_routes_index_option_and_risk_without_execution():
    response = AgentLoop().handle(AgentRequest(
        text='Analyze NAS100 options: compare the index movement with the underlying and Greeks.',
        symbol='NAS100',
    ))
    assert response.status == 'accepted'
    assert 'Index Brain' in response.routed_brains
    assert 'Option Brain' in response.routed_brains
    assert 'Risk Brain' in response.routed_brains
    assert response.safety['execution_authorized'] is False
