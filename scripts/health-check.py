#!/usr/bin/env python3
"""
RedELK Health Check Script
Version 3.0.0

Comprehensive health check for all RedELK services.
Can be run standalone or integrated with monitoring systems.
"""

import sys
import subprocess
import json
import time
from pathlib import Path
from typing import Dict, List, Tuple

try:
    from rich.console import Console
    from rich.table import Table
    from rich import box
except ImportError:
    print("📦 Installing required dependencies...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "rich>=13.0.0"])
    from rich.console import Console
    from rich.table import Table
    from rich import box

console = Console()

SERVICES = [
    {
        'name': 'Elasticsearch',
        'container': 'redelk-elasticsearch',
        'check_cmd': ['curl', '-k', '-s', '-u', 'elastic:${ELASTIC_PASSWORD}', 
                      'https://localhost:9200/_cluster/health'],
        'check_key': 'status',
        'healthy_values': ['green', 'yellow']
    },
    {
        'name': 'Logstash',
        'container': 'redelk-logstash',
        'check_cmd': ['curl', '-s', 'http://localhost:9600'],
        'check_key': None,
        'healthy_values': None
    },
    {
        'name': 'Kibana',
        'container': 'redelk-kibana',
        'check_cmd': ['curl', '-k', '-s', 'https://localhost:5601/api/status'],
        'check_key': 'status',
        'healthy_values': ['available']
    },
    {
        'name': 'NGINX',
        'container': 'redelk-nginx',
        'check_cmd': ['curl', '-s', '-o', '/dev/null', '-w', '%{http_code}', 'http://localhost:80'],
        'check_key': None,
        'healthy_values': ['200', '301', '302']
    },
    {
        'name': 'RedELK Base',
        'container': 'redelk-base',
        'check_cmd': ['pgrep', 'cron'],
        'check_key': None,
        'healthy_values': None
    },
    {
        'name': 'Jupyter',
        'container': 'redelk-jupyter',
        'check_cmd': ['curl', '-s', '-o', '/dev/null', '-w', '%{http_code}', 'http://localhost:8888'],
        'check_key': None,
        'healthy_values': ['200', '302']
    },
    {
        'name': 'Neo4j',
        'container': 'redelk-bloodhound-neo4j',
        'check_cmd': ['curl', '-s', 'http://localhost:7474'],
        'check_key': None,
        'healthy_values': None
    },
    {
        'name': 'PostgreSQL',
        'container': 'redelk-bloodhound-postgres',
        'check_cmd': ['pg_isready', '-U', 'bloodhound'],
        'check_key': None,
        'healthy_values': None
    },
    {
        'name': 'BloodHound',
        'container': 'redelk-bloodhound-app',
        'check_cmd': ['curl', '-s', '-o', '/dev/null', '-w', '%{http_code}', 'http://localhost:8080'],
        'check_key': None,
        'healthy_values': ['200']
    }
]


def check_docker_running() -> bool:
    """Check if Docker daemon is running"""
    try:
        subprocess.run(['docker', 'ps'], capture_output=True, check=True, timeout=5)
        return True
    except:
        return False


def get_container_status(container_name: str) -> Tuple[str, str]:
    """Get container status and health"""
    try:
        # Get status
        result = subprocess.run([
            'docker', 'inspect', 
            '--format={{.State.Status}}', 
            container_name
        ], capture_output=True, text=True, timeout=5)
        
        status = result.stdout.strip() if result.returncode == 0 else 'not found'
        
        # Get health if available
        result = subprocess.run([
            'docker', 'inspect',
            '--format={{.State.Health.Status}}',
            container_name
        ], capture_output=True, text=True, timeout=5)
        
        health = result.stdout.strip() if result.returncode == 0 and result.stdout.strip() else 'none'
        
        return status, health
        
    except Exception:
        return 'unknown', 'unknown'


def check_service_health(service: Dict) -> Dict:
    """Check health of a specific service"""
    result = {
        'name': service['name'],
        'container': service['container'],
        'status': 'unknown',
        'health': 'unknown',
        'check_result': 'unknown'
    }
    
    # Check container status
    status, health = get_container_status(service['container'])
    result['status'] = status
    result['health'] = health
    
    # If container is not running, return early
    if status != 'running':
        result['check_result'] = 'container not running'
        return result
    
    # Perform service-specific health check
    try:
        cmd = ['docker', 'exec', service['container']] + service['check_cmd']
        exec_result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10
        )
        
        if exec_result.returncode == 0:
            output = exec_result.stdout.strip()
            
            # Parse JSON response if applicable
            if service['check_key']:
                try:
                    data = json.loads(output)
                    value = data.get(service['check_key'])
                    if value in service['healthy_values']:
                        result['check_result'] = 'healthy'
                    else:
                        result['check_result'] = f'unhealthy ({value})'
                except json.JSONDecodeError:
                    result['check_result'] = 'json parse error'
            else:
                # Check HTTP codes or command success
                if service['healthy_values']:
                    if output in service['healthy_values']:
                        result['check_result'] = 'healthy'
                    else:
                        result['check_result'] = f'unhealthy ({output})'
                else:
                    result['check_result'] = 'healthy'
        else:
            result['check_result'] = f'check failed ({exec_result.returncode})'
            
    except subprocess.TimeoutExpired:
        result['check_result'] = 'timeout'
    except Exception as e:
        result['check_result'] = f'error: {str(e)}'
    
    return result


def display_results(results: List[Dict], verbose: bool = False):
    """Display health check results"""
    console.print("\n[bold cyan]🏥 RedELK Health Check Results[/bold cyan]\n")
    
    table = Table(show_header=True, header_style="bold magenta", box=box.ROUNDED)
    table.add_column("Service", style="cyan", width=20)
    table.add_column("Container Status", width=15)
    table.add_column("Docker Health", width=15)
    table.add_column("Service Check", width=20)
    
    healthy_count = 0
    total_count = len(results)
    
    for result in results:
        # Format status
        if result['status'] == 'running':
            status_fmt = "[green]running[/green]"
        elif result['status'] == 'exited':
            status_fmt = "[red]exited[/red]"
        elif result['status'] == 'not found':
            status_fmt = "[dim]not found[/dim]"
        else:
            status_fmt = f"[yellow]{result['status']}[/yellow]"
        
        # Format health
        if result['health'] == 'healthy':
            health_fmt = "[green]✅ healthy[/green]"
        elif result['health'] == 'unhealthy':
            health_fmt = "[red]❌ unhealthy[/red]"
        elif result['health'] == 'starting':
            health_fmt = "[yellow]🔄 starting[/yellow]"
        elif result['health'] == 'none':
            health_fmt = "[dim]no check[/dim]"
        else:
            health_fmt = f"[dim]{result['health']}[/dim]"
        
        # Format check result
        if 'healthy' in result['check_result']:
            check_fmt = "[green]✅ healthy[/green]"
            healthy_count += 1
        elif 'unhealthy' in result['check_result']:
            check_fmt = f"[red]❌ {result['check_result']}[/red]"
        elif 'timeout' in result['check_result']:
            check_fmt = "[yellow]⏱️  timeout[/yellow]"
        elif 'error' in result['check_result']:
            check_fmt = f"[red]{result['check_result']}[/red]"
        elif 'not running' in result['check_result']:
            check_fmt = "[red]❌ not running[/red]"
        else:
            check_fmt = f"[dim]{result['check_result']}[/dim]"
        
        table.add_row(
            result['name'],
            status_fmt,
            health_fmt,
            check_fmt
        )
    
    console.print(table)
    console.print()
    
    # Summary
    if healthy_count == total_count:
        console.print(f"[bold green]✅ All services healthy ({healthy_count}/{total_count})[/bold green]\n")
        return 0
    elif healthy_count > total_count / 2:
        console.print(f"[yellow]⚠️  Some services unhealthy ({healthy_count}/{total_count})[/yellow]\n")
        return 1
    else:
        console.print(f"[red]❌ Multiple services unhealthy ({healthy_count}/{total_count})[/red]\n")
        return 2


def main():
    """Main execution"""
    import argparse
    
    parser = argparse.ArgumentParser(description='RedELK Health Check')
    parser.add_argument('-v', '--verbose', action='store_true', help='Verbose output')
    parser.add_argument('--json', action='store_true', help='Output as JSON')
    parser.add_argument('--nagios', action='store_true', help='Nagios-compatible output')
    args = parser.parse_args()
    
    # Check Docker is running
    if not check_docker_running():
        console.print("[red]❌ Docker is not running or not accessible[/red]")
        return 3
    
    # Check all services
    results = []
    for service in SERVICES:
        result = check_service_health(service)
        results.append(result)
        if args.verbose:
            console.print(f"Checked {service['name']}...")
    
    # Display results
    if args.json:
        print(json.dumps(results, indent=2))
        return 0
    elif args.nagios:
        # Nagios format: STATUS | performance data
        healthy = sum(1 for r in results if 'healthy' in r['check_result'])
        total = len(results)
        if healthy == total:
            print(f"OK - All {total} services healthy | healthy={healthy};{total};0;0;{total}")
            return 0
        elif healthy > total / 2:
            print(f"WARNING - {healthy}/{total} services healthy | healthy={healthy};{total};0;0;{total}")
            return 1
        else:
            print(f"CRITICAL - Only {healthy}/{total} services healthy | healthy={healthy};{total};0;0;{total}")
            return 2
    else:
        return display_results(results, args.verbose)


if __name__ == "__main__":
    sys.exit(main())


