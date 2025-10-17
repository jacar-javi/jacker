#!/usr/bin/env python3
"""
Resource Manager - Automated Resource Monitoring and Management
Monitors container resource usage via Prometheus and triggers adjustments
"""

import os
import sys
import time
import logging
import yaml
import json
import subprocess
from datetime import datetime, timedelta
from collections import defaultdict
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass, field

import requests
from prometheus_api_client import PrometheusConnect
import docker


# ====================================================================
# DATA CLASSES
# ====================================================================
@dataclass
class ResourceMetrics:
    """Container resource metrics"""
    cpu_usage: float = 0.0
    memory_usage: float = 0.0
    cpu_limit: float = 0.0
    memory_limit: float = 0.0
    cpu_percent: float = 0.0
    memory_percent: float = 0.0
    timestamp: datetime = field(default_factory=datetime.now)


@dataclass
class AdjustmentDecision:
    """Resource adjustment decision"""
    service_name: str
    action: str  # 'increase', 'decrease', 'none'
    resource_type: str  # 'cpu', 'memory', 'both'
    current_cpu: float = 0.0
    current_memory: str = ""
    new_cpu: float = 0.0
    new_memory: str = ""
    reason: str = ""


@dataclass
class ServiceState:
    """Track service state for hysteresis"""
    consecutive_high_cpu: int = 0
    consecutive_low_cpu: int = 0
    consecutive_high_memory: int = 0
    consecutive_low_memory: int = 0
    last_adjustment: Optional[datetime] = None
    adjustments_today: int = 0
    last_reset: datetime = field(default_factory=datetime.now)


# ====================================================================
# RESOURCE MANAGER CLASS
# ====================================================================
class ResourceManager:
    """Main resource manager class"""

    def __init__(self, config_path: str = "/config/config.yml"):
        self.config = self._load_config(config_path)
        self.logger = self._setup_logging()
        self.prometheus = self._setup_prometheus()
        self.docker_client = self._setup_docker()
        self.service_states: Dict[str, ServiceState] = defaultdict(ServiceState)
        self.logger.info("Resource Manager initialized")

    def _load_config(self, config_path: str) -> dict:
        """Load configuration from YAML file"""
        with open(config_path, 'r') as f:
            return yaml.safe_load(f)

    def _setup_logging(self) -> logging.Logger:
        """Setup logging configuration"""
        log_level = os.getenv('LOG_LEVEL', 'info').upper()
        log_file = os.getenv('LOG_FILE', '/logs/resource-manager.log')

        # Create logger
        logger = logging.getLogger('ResourceManager')
        logger.setLevel(getattr(logging, log_level))

        # Console handler
        console_handler = logging.StreamHandler(sys.stdout)
        console_handler.setLevel(logging.INFO)
        console_formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
        console_handler.setFormatter(console_formatter)
        logger.addHandler(console_handler)

        # File handler
        try:
            os.makedirs(os.path.dirname(log_file), exist_ok=True)
            file_handler = logging.FileHandler(log_file)
            file_handler.setLevel(logging.DEBUG)
            file_formatter = logging.Formatter(
                '%(asctime)s - %(name)s - %(levelname)s - %(funcName)s - %(message)s'
            )
            file_handler.setFormatter(file_formatter)
            logger.addHandler(file_handler)
        except Exception as e:
            logger.warning(f"Could not setup file logging: {e}")

        return logger

    def _setup_prometheus(self) -> PrometheusConnect:
        """Setup Prometheus connection"""
        prometheus_url = os.getenv(
            'PROMETHEUS_URL',
            self.config['monitoring']['prometheus_url']
        )
        self.logger.info(f"Connecting to Prometheus at {prometheus_url}")
        return PrometheusConnect(url=prometheus_url, disable_ssl=True)

    def _setup_docker(self) -> docker.DockerClient:
        """Setup Docker client connection"""
        docker_host = os.getenv(
            'DOCKER_HOST',
            self.config['docker']['host']
        )
        self.logger.info(f"Connecting to Docker at {docker_host}")
        return docker.DockerClient(base_url=docker_host)

    # ====================================================================
    # PROMETHEUS QUERY FUNCTIONS
    # ====================================================================
    def query_container_cpu_usage(self, service_name: str) -> float:
        """Query container CPU usage from Prometheus"""
        try:
            # Query: rate of CPU usage over analysis window
            query = f'rate(container_cpu_usage_seconds_total{{name=~".*{service_name}.*"}}[{self.config["monitoring"]["analysis_window"]}])'
            result = self.prometheus.custom_query(query)

            if result:
                # Return the most recent value
                return float(result[0]['value'][1])
            return 0.0
        except Exception as e:
            self.logger.error(f"Error querying CPU usage for {service_name}: {e}")
            return 0.0

    def query_container_memory_usage(self, service_name: str) -> float:
        """Query container memory usage from Prometheus"""
        try:
            query = f'container_memory_usage_bytes{{name=~".*{service_name}.*"}}'
            result = self.prometheus.custom_query(query)

            if result:
                return float(result[0]['value'][1])
            return 0.0
        except Exception as e:
            self.logger.error(f"Error querying memory usage for {service_name}: {e}")
            return 0.0

    def query_container_cpu_limit(self, service_name: str) -> float:
        """Query container CPU limit from Prometheus"""
        try:
            query = f'container_spec_cpu_quota{{name=~".*{service_name}.*"}} / 100000'
            result = self.prometheus.custom_query(query)

            if result:
                return float(result[0]['value'][1])
            return 0.0
        except Exception as e:
            self.logger.error(f"Error querying CPU limit for {service_name}: {e}")
            return 0.0

    def query_container_memory_limit(self, service_name: str) -> float:
        """Query container memory limit from Prometheus"""
        try:
            query = f'container_spec_memory_limit_bytes{{name=~".*{service_name}.*"}}'
            result = self.prometheus.custom_query(query)

            if result:
                return float(result[0]['value'][1])
            return 0.0
        except Exception as e:
            self.logger.error(f"Error querying memory limit for {service_name}: {e}")
            return 0.0

    def get_container_metrics(self, service_name: str) -> ResourceMetrics:
        """Get comprehensive resource metrics for a service"""
        metrics = ResourceMetrics()

        try:
            metrics.cpu_usage = self.query_container_cpu_usage(service_name)
            metrics.memory_usage = self.query_container_memory_usage(service_name)
            metrics.cpu_limit = self.query_container_cpu_limit(service_name)
            metrics.memory_limit = self.query_container_memory_limit(service_name)

            # Calculate percentages
            if metrics.cpu_limit > 0:
                metrics.cpu_percent = metrics.cpu_usage / metrics.cpu_limit
            if metrics.memory_limit > 0:
                metrics.memory_percent = metrics.memory_usage / metrics.memory_limit

            self.logger.debug(
                f"{service_name}: CPU {metrics.cpu_percent:.1%}, "
                f"Memory {metrics.memory_percent:.1%}"
            )

        except Exception as e:
            self.logger.error(f"Error getting metrics for {service_name}: {e}")

        return metrics

    # ====================================================================
    # ANALYSIS FUNCTIONS
    # ====================================================================
    def analyze_resource_usage(self, service_name: str) -> AdjustmentDecision:
        """Analyze resource usage and determine if adjustment is needed"""
        metrics = self.get_container_metrics(service_name)
        state = self.service_states[service_name]

        decision = AdjustmentDecision(
            service_name=service_name,
            action='none',
            resource_type='none',
            current_cpu=metrics.cpu_limit,
            current_memory=self._bytes_to_mb(metrics.memory_limit)
        )

        # Check CPU usage
        cpu_high = os.getenv('CPU_HIGH_THRESHOLD', self.config['thresholds']['cpu_high'])
        cpu_low = os.getenv('CPU_LOW_THRESHOLD', self.config['thresholds']['cpu_low'])

        if metrics.cpu_percent > float(cpu_high):
            state.consecutive_high_cpu += 1
            state.consecutive_low_cpu = 0
        elif metrics.cpu_percent < float(cpu_low):
            state.consecutive_low_cpu += 1
            state.consecutive_high_cpu = 0
        else:
            state.consecutive_high_cpu = 0
            state.consecutive_low_cpu = 0

        # Check memory usage
        mem_high = os.getenv('MEMORY_HIGH_THRESHOLD', self.config['thresholds']['memory_high'])
        mem_low = os.getenv('MEMORY_LOW_THRESHOLD', self.config['thresholds']['memory_low'])

        if metrics.memory_percent > float(mem_high):
            state.consecutive_high_memory += 1
            state.consecutive_low_memory = 0
        elif metrics.memory_percent < float(mem_low):
            state.consecutive_low_memory += 1
            state.consecutive_high_memory = 0
        else:
            state.consecutive_high_memory = 0
            state.consecutive_low_memory = 0

        # Determine action based on consecutive checks (hysteresis)
        consecutive_required = self.config['thresholds']['consecutive_checks']

        if state.consecutive_high_cpu >= consecutive_required:
            decision.action = 'increase'
            decision.resource_type = 'cpu'
            decision.reason = f"CPU usage {metrics.cpu_percent:.1%} > {cpu_high} for {state.consecutive_high_cpu} checks"

        elif state.consecutive_high_memory >= consecutive_required:
            if decision.action == 'increase':
                decision.resource_type = 'both'
            else:
                decision.action = 'increase'
                decision.resource_type = 'memory'
            decision.reason = f"Memory usage {metrics.memory_percent:.1%} > {mem_high} for {state.consecutive_high_memory} checks"

        elif state.consecutive_low_cpu >= consecutive_required and service_name not in self.config['services']['critical']:
            decision.action = 'decrease'
            decision.resource_type = 'cpu'
            decision.reason = f"CPU usage {metrics.cpu_percent:.1%} < {cpu_low} for {state.consecutive_low_cpu} checks"

        elif state.consecutive_low_memory >= consecutive_required and service_name not in self.config['services']['critical']:
            if decision.action == 'decrease':
                decision.resource_type = 'both'
            else:
                decision.action = 'decrease'
                decision.resource_type = 'memory'
            decision.reason = f"Memory usage {metrics.memory_percent:.1%} < {mem_low} for {state.consecutive_low_memory} checks"

        # Calculate new resource limits if adjustment needed
        if decision.action != 'none':
            decision.new_cpu, decision.new_memory = self.calculate_adjustment(
                metrics.cpu_limit,
                metrics.memory_limit,
                decision.action,
                decision.resource_type,
                service_name
            )

        return decision

    def calculate_adjustment(
        self,
        current_cpu: float,
        current_memory: float,
        action: str,
        resource_type: str,
        service_name: str
    ) -> Tuple[float, str]:
        """Calculate new resource limits based on adjustment action"""
        new_cpu = current_cpu
        new_memory = current_memory

        increase_factor = float(os.getenv('INCREASE_FACTOR', self.config['adjustment']['increase_factor']))
        decrease_factor = float(os.getenv('DECREASE_FACTOR', self.config['adjustment']['decrease_factor']))

        min_cpu = self.config['adjustment']['min_cpu']
        max_cpu = self.config['adjustment']['max_cpu']
        min_memory = self._parse_memory_string(self.config['adjustment']['min_memory'])
        max_memory = self._parse_memory_string(self.config['adjustment']['max_memory'])

        # Get baseline for critical services
        baseline = self.config['services'].get('baseline', {}).get(service_name, {})
        baseline_cpu = baseline.get('cpu', min_cpu)
        baseline_memory = self._parse_memory_string(baseline.get('memory', '64M'))

        # Adjust CPU
        if resource_type in ['cpu', 'both']:
            if action == 'increase':
                new_cpu = min(current_cpu * increase_factor, max_cpu)
            elif action == 'decrease':
                new_cpu = max(current_cpu * decrease_factor, max(min_cpu, baseline_cpu))

        # Adjust Memory
        if resource_type in ['memory', 'both']:
            if action == 'increase':
                new_memory = min(current_memory * increase_factor, max_memory)
            elif action == 'decrease':
                new_memory = max(current_memory * decrease_factor, max(min_memory, baseline_memory))

        return round(new_cpu, 2), self._bytes_to_mb(new_memory)

    def should_adjust_resources(self, service_name: str, decision: AdjustmentDecision) -> bool:
        """Determine if resource adjustment should be performed"""
        if decision.action == 'none':
            return False

        state = self.service_states[service_name]

        # Check cooldown period
        cooldown = self.config['adjustment']['cooldown_period']
        if state.last_adjustment:
            time_since_adjustment = (datetime.now() - state.last_adjustment).total_seconds()
            if time_since_adjustment < cooldown:
                self.logger.info(
                    f"{service_name}: In cooldown period "
                    f"({int(cooldown - time_since_adjustment)}s remaining)"
                )
                return False

        # Check daily adjustment limit
        if state.last_reset.date() != datetime.now().date():
            state.adjustments_today = 0
            state.last_reset = datetime.now()

        max_adjustments = self.config['adjustment']['max_adjustments_per_day']
        if state.adjustments_today >= max_adjustments:
            self.logger.warning(
                f"{service_name}: Daily adjustment limit reached "
                f"({state.adjustments_today}/{max_adjustments})"
            )
            return False

        # Check if in dry-run mode
        if self.config['automation']['dry_run']:
            self.logger.info(
                f"[DRY RUN] Would adjust {service_name}: {decision.action} "
                f"{decision.resource_type} - {decision.reason}"
            )
            return False

        return True

    # ====================================================================
    # DEPLOYMENT FUNCTIONS
    # ====================================================================
    def trigger_deployment(self, decision: AdjustmentDecision) -> bool:
        """Trigger resource adjustment deployment"""
        service_name = decision.service_name

        if self.config['blue_green']['enabled']:
            return self.trigger_blue_green_deployment(decision)
        else:
            return self.trigger_direct_adjustment(decision)

    def trigger_blue_green_deployment(self, decision: AdjustmentDecision) -> bool:
        """Trigger blue-green deployment for zero-downtime updates"""
        try:
            script_path = self.config['blue_green']['script']

            # Prepare command
            cmd = [
                script_path,
                decision.service_name,
                str(decision.new_cpu),
                decision.new_memory
            ]

            self.logger.info(
                f"Triggering blue-green deployment for {decision.service_name}: "
                f"CPU {decision.current_cpu} -> {decision.new_cpu}, "
                f"Memory {decision.current_memory} -> {decision.new_memory}"
            )

            # Execute blue-green deployment script
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=self.config['blue_green']['health_check_timeout']
            )

            if result.returncode == 0:
                self.logger.info(
                    f"Blue-green deployment successful for {decision.service_name}"
                )
                self._update_adjustment_state(decision.service_name)
                self._send_notification('blue_green_deployment', decision)
                return True
            else:
                self.logger.error(
                    f"Blue-green deployment failed for {decision.service_name}: "
                    f"{result.stderr}"
                )
                self._send_notification('deployment_failure', decision)
                return False

        except subprocess.TimeoutExpired:
            self.logger.error(
                f"Blue-green deployment timeout for {decision.service_name}"
            )
            return False
        except Exception as e:
            self.logger.error(
                f"Error triggering blue-green deployment for {decision.service_name}: {e}"
            )
            return False

    def trigger_direct_adjustment(self, decision: AdjustmentDecision) -> bool:
        """Trigger direct resource adjustment via Docker API"""
        try:
            container = self.docker_client.containers.get(decision.service_name)

            # Update container resources
            cpu_limit = int(decision.new_cpu * 100000)  # Convert to CPU quota
            memory_limit = self._parse_memory_string(decision.new_memory)

            container.update(
                cpu_quota=cpu_limit,
                mem_limit=memory_limit
            )

            self.logger.info(
                f"Direct adjustment applied to {decision.service_name}: "
                f"CPU {decision.current_cpu} -> {decision.new_cpu}, "
                f"Memory {decision.current_memory} -> {decision.new_memory}"
            )

            self._update_adjustment_state(decision.service_name)
            self._send_notification('resource_adjustment', decision)
            return True

        except Exception as e:
            self.logger.error(
                f"Error applying direct adjustment to {decision.service_name}: {e}"
            )
            return False

    def _update_adjustment_state(self, service_name: str):
        """Update service state after adjustment"""
        state = self.service_states[service_name]
        state.last_adjustment = datetime.now()
        state.adjustments_today += 1
        state.consecutive_high_cpu = 0
        state.consecutive_low_cpu = 0
        state.consecutive_high_memory = 0
        state.consecutive_low_memory = 0

    # ====================================================================
    # NOTIFICATION FUNCTIONS
    # ====================================================================
    def _send_notification(self, event_type: str, decision: AdjustmentDecision):
        """Send notification about resource adjustment"""
        if not self.config['notifications']['enabled']:
            return

        if event_type not in self.config['notifications']['events']:
            return

        message = {
            'event': event_type,
            'service': decision.service_name,
            'action': decision.action,
            'resource_type': decision.resource_type,
            'reason': decision.reason,
            'timestamp': datetime.now().isoformat()
        }

        # Alertmanager notification
        if self.config['notifications']['channels']['alertmanager']['enabled']:
            self._send_alertmanager_notification(message)

        # Log notification
        if self.config['notifications']['channels']['logfile']['enabled']:
            self.logger.info(f"NOTIFICATION: {json.dumps(message)}")

    def _send_alertmanager_notification(self, message: dict):
        """Send notification to Alertmanager"""
        try:
            alertmanager_url = self.config['notifications']['channels']['alertmanager']['url']
            alerts = [{
                'labels': {
                    'alertname': 'ResourceAdjustment',
                    'service': message['service'],
                    'severity': 'info'
                },
                'annotations': {
                    'summary': f"Resource adjustment for {message['service']}",
                    'description': message['reason']
                }
            }]

            response = requests.post(
                f"{alertmanager_url}/api/v1/alerts",
                json=alerts,
                timeout=10
            )
            response.raise_for_status()

        except Exception as e:
            self.logger.error(f"Error sending Alertmanager notification: {e}")

    # ====================================================================
    # UTILITY FUNCTIONS
    # ====================================================================
    def _bytes_to_mb(self, bytes_value: float) -> str:
        """Convert bytes to MB string"""
        if bytes_value == 0:
            return "0M"
        mb_value = int(bytes_value / (1024 * 1024))
        return f"{mb_value}M"

    def _parse_memory_string(self, memory_str: str) -> float:
        """Parse memory string (e.g., '256M') to bytes"""
        if not memory_str:
            return 0.0

        units = {'K': 1024, 'M': 1024**2, 'G': 1024**3}
        number = float(''.join(filter(str.isdigit, memory_str)))
        unit = ''.join(filter(str.isalpha, memory_str)).upper()

        return number * units.get(unit, 1)

    # ====================================================================
    # HEALTH CHECK ENDPOINT
    # ====================================================================
    def start_health_endpoint(self):
        """Start health check HTTP endpoint"""
        from http.server import HTTPServer, BaseHTTPRequestHandler
        import threading

        class HealthHandler(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path == '/health':
                    self.send_response(200)
                    self.send_header('Content-Type', 'application/json')
                    self.end_headers()
                    response = {
                        'status': 'healthy',
                        'timestamp': datetime.now().isoformat()
                    }
                    self.wfile.write(json.dumps(response).encode())
                elif self.path == '/metrics':
                    self.send_response(200)
                    self.send_header('Content-Type', 'text/plain')
                    self.end_headers()
                    # TODO: Add Prometheus metrics
                    self.wfile.write(b'# Resource Manager Metrics\n')
                else:
                    self.send_response(404)
                    self.end_headers()

            def log_message(self, format, *args):
                pass  # Suppress logging

        port = self.config['metrics']['port']
        server = HTTPServer(('0.0.0.0', port), HealthHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.logger.info(f"Health endpoint started on port {port}")

    # ====================================================================
    # MAIN LOOP
    # ====================================================================
    def run(self):
        """Main monitoring loop"""
        self.logger.info("Starting resource monitoring loop")

        # Start health endpoint
        if self.config['metrics']['enabled']:
            self.start_health_endpoint()

        check_interval = int(os.getenv(
            'CHECK_INTERVAL',
            self.config['monitoring']['check_interval']
        ))

        while True:
            try:
                self.logger.info("=" * 60)
                self.logger.info("Starting resource check cycle")

                for service_name in self.config['services']['monitored']:
                    self.logger.debug(f"Checking {service_name}...")

                    # Analyze resource usage
                    decision = self.analyze_resource_usage(service_name)

                    # Check if adjustment is needed
                    if self.should_adjust_resources(service_name, decision):
                        self.logger.info(
                            f"{service_name}: Adjustment needed - {decision.reason}"
                        )

                        if self.config['automation']['enabled']:
                            success = self.trigger_deployment(decision)
                            if success:
                                self.logger.info(
                                    f"{service_name}: Resource adjustment successful"
                                )
                            else:
                                self.logger.error(
                                    f"{service_name}: Resource adjustment failed"
                                )

                self.logger.info(f"Check cycle complete. Sleeping {check_interval}s")
                time.sleep(check_interval)

            except KeyboardInterrupt:
                self.logger.info("Received shutdown signal")
                break
            except Exception as e:
                self.logger.error(f"Error in monitoring loop: {e}", exc_info=True)
                time.sleep(60)  # Wait before retrying


# ====================================================================
# MAIN ENTRY POINT
# ====================================================================
def main():
    """Main entry point"""
    config_path = os.getenv('CONFIG_PATH', '/config/config.yml')

    # Wait for Prometheus to be ready
    prometheus_url = os.getenv('PROMETHEUS_URL', 'http://prometheus:9090')
    print(f"Waiting for Prometheus at {prometheus_url}...")

    while True:
        try:
            response = requests.get(f"{prometheus_url}/-/ready", timeout=5)
            if response.status_code == 200:
                print("Prometheus is ready!")
                break
        except Exception:
            pass
        print("Waiting for Prometheus...")
        time.sleep(5)

    # Initialize and run resource manager
    manager = ResourceManager(config_path)
    manager.run()


if __name__ == "__main__":
    main()
