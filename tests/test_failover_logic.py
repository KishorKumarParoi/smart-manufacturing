import unittest
from unittest.mock import patch, MagicMock
from src.failover.health_probe import MultiCloudHealthProber

class TestMultiCloudFailover(unittest.TestCase):
    def setUp(self):
        self.prober = MultiCloudHealthProber(
            primary_url="http://mock-aws/health",
            secondary_url="http://mock-gcp/health",
            unhealthy_threshold=3
        )

    @patch("requests.get")
    def test_normal_operation_primary_healthy(self, mock_get):
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {"status": "HEALTHY", "cloud": "aws"}
        mock_get.return_value = mock_resp

        status = self.prober.run_probe_cycle()
        self.assertTrue(status["primary"]["healthy"])
        self.assertEqual(self.prober.active_cloud, "AWS (Primary: us-east-1)")
        self.assertEqual(self.prober.consecutive_primary_failures, 0)

    @patch("requests.get")
    def test_failover_trigger_after_consecutive_failures(self, mock_get):
        def mock_side_effect(url, timeout=3.0):
            mock_resp = MagicMock()
            if "mock-aws" in url:
                mock_resp.status_code = 503
            else:
                mock_resp.status_code = 200
                mock_resp.json.return_value = {"status": "HEALTHY", "cloud": "gcp"}
            return mock_resp

        mock_get.side_effect = mock_side_effect

        # Failures 1 and 2: Still on AWS
        self.prober.run_probe_cycle()
        self.assertEqual(self.prober.consecutive_primary_failures, 1)
        self.assertEqual(self.prober.active_cloud, "AWS (Primary: us-east-1)")

        self.prober.run_probe_cycle()
        self.assertEqual(self.prober.consecutive_primary_failures, 2)
        self.assertEqual(self.prober.active_cloud, "AWS (Primary: us-east-1)")

        # Failure 3: Triggers failover to GCP
        self.prober.run_probe_cycle()
        self.assertEqual(self.prober.consecutive_primary_failures, 3)
        self.assertEqual(self.prober.active_cloud, "GCP (Secondary: us-central1)")

    @patch("requests.get")
    def test_primary_recovery_and_failback(self, mock_get):
        # Set prober into failed-over state
        self.prober.active_cloud = "GCP (Secondary: us-central1)"
        self.prober.consecutive_primary_failures = 3

        # Now primary recovers
        mock_resp = MagicMock()
        mock_resp.status_code = 200
        mock_resp.json.return_value = {"status": "HEALTHY"}
        mock_get.return_value = mock_resp

        self.prober.run_probe_cycle()
        self.assertEqual(self.prober.active_cloud, "AWS (Primary: us-east-1)")
        self.assertEqual(self.prober.consecutive_primary_failures, 0)

if __name__ == "__main__":
    unittest.main()
