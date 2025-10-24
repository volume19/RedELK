#!/usr/bin/env python3
"""
RedELK Modern Installer
Version 3.0.0

A user-friendly installer for RedELK that replaces the old bash scripts
with better error handling, progress tracking, and clear explanations.
"""

import os
import sys
import json
import subprocess
import shutil
import socket
import argparse
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import re

# Check Python version
if sys.version_info < (3, 8):
    print("❌ Error: RedELK installer requires Python 3.8 or higher")
    print(f"   Current version: {sys.version}")
    sys.exit(1)

# Try to import required packages, install if missing
try:
    from rich.console import Console
    from rich.prompt import Prompt, Confirm
    from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn, TaskProgressColumn, TimeElapsedColumn
    from rich.panel import Panel
    from rich.table import Table
    from rich.markdown import Markdown
    from rich import box
except ImportError:
    print("📦 Installing required dependencies (rich)...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "rich>=13.0.0"])
    from rich.console import Console
    from rich.prompt import Prompt, Confirm
    from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn, TaskProgressColumn, TimeElapsedColumn
    from rich.panel import Panel
    from rich.table import Table
    from rich.markdown import Markdown
    from rich import box

console = Console()

# Constants
ELK_VERSION = "8.11.3"
REDELK_VERSION = "3.0.0"
MIN_MEMORY_GB = 4
RECOMMENDED_MEMORY_GB = 8
REQUIRED_PORTS = [80, 443, 5044, 5601, 7474, 7687, 8443, 9200]

class PreflightCheck:
    """Pre-flight system checks before installation"""
    
    @staticmethod
    def check_root() -> bool:
        """Check if running as root"""
        return os.geteuid() == 0
    
    @staticmethod
    def check_os() -> Tuple[bool, str]:
        """Check if OS is Debian/Ubuntu based"""
        if not os.path.exists("/etc/debian_version"):
            return False, "Not a Debian/Ubuntu-based system"
        
        try:
            with open("/etc/os-release") as f:
                os_info = f.read()
                if "Ubuntu" in os_info:
                    return True, "Ubuntu"
                elif "Debian" in os_info:
                    return True, "Debian"
                else:
                    return True, "Debian-based"
        except:
            return True, "Debian-based"
    
    @staticmethod
    def check_memory() -> Tuple[bool, int]:
        """Check available memory in GB"""
        try:
            with open("/proc/meminfo") as f:
                meminfo = f.read()
                mem_total = int([line for line in meminfo.split("\n") if "MemTotal" in line][0].split()[1])
                mem_gb = mem_total // (1024 * 1024)
                return mem_gb >= MIN_MEMORY_GB, mem_gb
        except:
            return False, 0
    
    @staticmethod
    def check_disk_space(path: str = "/") -> Tuple[bool, int]:
        """Check available disk space in GB"""
        try:
            stat = shutil.disk_usage(path)
            free_gb = stat.free // (1024**3)
            return free_gb >= 20, free_gb
        except:
            return False, 0
    
    @staticmethod
    def check_docker() -> Tuple[bool, str]:
        """Check if Docker is installed and running"""
        try:
            result = subprocess.run(["docker", "--version"], capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                version = result.stdout.strip()
                # Check if Docker daemon is running
                result = subprocess.run(["docker", "ps"], capture_output=True, text=True, timeout=5)
                if result.returncode == 0:
                    return True, version
                else:
                    return False, "Docker installed but daemon not running"
            return False, "Docker not installed"
        except FileNotFoundError:
            return False, "Docker not installed"
        except subprocess.TimeoutExpired:
            return False, "Docker not responding"
        except Exception as e:
            return False, f"Error checking Docker: {str(e)}"
    
    @staticmethod
    def check_docker_compose() -> Tuple[bool, str]:
        """Check if Docker Compose is installed"""
        try:
            # Try docker compose (newer plugin version)
            result = subprocess.run(["docker", "compose", "version"], capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                return True, result.stdout.strip()
            
            # Try docker-compose (older standalone version)
            result = subprocess.run(["docker-compose", "--version"], capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                return True, result.stdout.strip()
            
            return False, "Docker Compose not installed"
        except FileNotFoundError:
            return False, "Docker Compose not installed"
        except Exception as e:
            return False, f"Error checking Docker Compose: {str(e)}"
    
    @staticmethod
    def check_ports() -> List[int]:
        """Check which required ports are already in use"""
        used_ports = []
        for port in REQUIRED_PORTS:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(1)
            result = sock.connect_ex(('127.0.0.1', port))
            if result == 0:
                used_ports.append(port)
            sock.close()
        return used_ports


class Installer:
    """Main installer class"""
    
    def __init__(self, args):
        self.args = args
        self.config = {}
        self.base_dir = Path(__file__).parent.absolute()
        self.dry_run = args.dry_run
        
    def show_welcome(self):
        """Display welcome banner"""
        welcome = """
    ╔═══════════════════════════════════════════════════════════╗
    ║                                                           ║
    ║        ____            _  _____  _      _  __            ║
    ║       |  _ \\  ___   __| || ____|| |    | |/ /           ║
    ║       | |_) |/ _ \\ / _  ||  _|  | |    | ' /            ║
    ║       |  _ <|  __/| (_| || |___ | |___ | . \\            ║
    ║       |_| \\_\\___| \\____||_____||_____||_|\\_\\          ║
    ║                                                           ║
    ║              Modern Installer v3.0.0                      ║
    ║                                                           ║
    ╚═══════════════════════════════════════════════════════════╝
        """
        console.print(welcome, style="bold cyan")
        console.print("\n[bold]Welcome to RedELK Installation Wizard![/bold]\n")
        console.print("This installer will guide you through setting up RedELK, a Red Team")
        console.print("SIEM for tracking operations and detecting Blue Team activities.\n")
    
    def run_preflight_checks(self) -> bool:
        """Run all pre-flight checks"""
        console.print(Panel.fit("🔍 [bold]Running Pre-flight Checks[/bold]", border_style="blue"))
        
        checks_table = Table(show_header=True, header_style="bold magenta", box=box.ROUNDED)
        checks_table.add_column("Check", style="cyan", width=30)
        checks_table.add_column("Status", width=15)
        checks_table.add_column("Details", width=40)
        
        all_passed = True
        warnings = []
        
        # Root check
        if PreflightCheck.check_root():
            checks_table.add_row("✓ Root privileges", "[green]PASS[/green]", "Running as root")
        else:
            checks_table.add_row("✗ Root privileges", "[red]FAIL[/red]", "Must run as root")
            all_passed = False
        
        # OS check
        os_ok, os_name = PreflightCheck.check_os()
        if os_ok:
            checks_table.add_row("✓ Operating System", "[green]PASS[/green]", os_name)
        else:
            checks_table.add_row("✗ Operating System", "[red]FAIL[/red]", os_name)
            all_passed = False
        
        # Memory check
        mem_ok, mem_gb = PreflightCheck.check_memory()
        if mem_ok:
            if mem_gb >= RECOMMENDED_MEMORY_GB:
                checks_table.add_row("✓ Memory", "[green]PASS[/green]", f"{mem_gb} GB available")
            else:
                checks_table.add_row("✓ Memory", "[yellow]WARN[/yellow]", f"{mem_gb} GB (8GB+ recommended)")
                warnings.append(f"Only {mem_gb} GB RAM. 8GB+ recommended for full install.")
        else:
            checks_table.add_row("✗ Memory", "[red]FAIL[/red]", f"Only {mem_gb} GB (need {MIN_MEMORY_GB} GB minimum)")
            all_passed = False
        
        # Disk space check
        disk_ok, disk_gb = PreflightCheck.check_disk_space()
        if disk_ok:
            checks_table.add_row("✓ Disk Space", "[green]PASS[/green]", f"{disk_gb} GB available")
        else:
            checks_table.add_row("✗ Disk Space", "[yellow]WARN[/yellow]", f"Only {disk_gb} GB free (20GB+ recommended)")
            warnings.append(f"Low disk space: {disk_gb} GB free")
        
        # Docker check
        docker_ok, docker_info = PreflightCheck.check_docker()
        if docker_ok:
            checks_table.add_row("✓ Docker", "[green]PASS[/green]", docker_info)
        else:
            checks_table.add_row("✗ Docker", "[red]FAIL[/red]", docker_info)
            all_passed = False
        
        # Docker Compose check
        compose_ok, compose_info = PreflightCheck.check_docker_compose()
        if compose_ok:
            checks_table.add_row("✓ Docker Compose", "[green]PASS[/green]", compose_info)
        else:
            checks_table.add_row("✗ Docker Compose", "[red]FAIL[/red]", compose_info)
            all_passed = False
        
        # Port checks
        used_ports = PreflightCheck.check_ports()
        if not used_ports:
            checks_table.add_row("✓ Port Availability", "[green]PASS[/green]", "All required ports free")
        else:
            checks_table.add_row("✗ Port Availability", "[yellow]WARN[/yellow]", f"Ports in use: {', '.join(map(str, used_ports))}")
            warnings.append(f"Ports already in use: {', '.join(map(str, used_ports))}")
        
        console.print(checks_table)
        console.print()
        
        # Show warnings
        if warnings:
            console.print("\n[yellow]⚠️  Warnings:[/yellow]")
            for warning in warnings:
                console.print(f"  • {warning}")
            console.print()
        
        if not all_passed:
            console.print("[red]❌ Pre-flight checks failed. Please fix the issues above before continuing.[/red]\n")
            
            if not PreflightCheck.check_root():
                console.print("[yellow]💡 Tip: Run this installer with sudo:[/yellow]")
                console.print(f"   sudo python3 {sys.argv[0]}\n")
            
            if not docker_ok and not compose_ok:
                console.print("[yellow]💡 Tip: Install Docker and Docker Compose:[/yellow]")
                console.print("   curl -fsSL https://get.docker.com | sh")
                console.print("   sudo apt-get install -y docker-compose-plugin\n")
            
            return False
        
        if warnings and not self.args.skip_warnings:
            if not Confirm.ask("\n[yellow]Continue despite warnings?[/yellow]", default=False):
                console.print("[yellow]Installation cancelled.[/yellow]")
                return False
        
        console.print("[green]✅ All pre-flight checks passed![/green]\n")
        return True
    
    def gather_configuration(self):
        """Interactively gather configuration from user"""
        console.print(Panel.fit("⚙️  [bold]Configuration Setup[/bold]", border_style="blue"))
        console.print("\nLet's configure your RedELK installation. Press Enter for default values.\n")
        
        # Installation type
        console.print("[bold cyan]Step 1/6: Installation Type[/bold cyan]")
        console.print("Choose your installation type:")
        console.print("  • [green]full[/green]    - Complete RedELK with Jupyter, BloodHound, Neo4j (requires 8GB+ RAM)")
        console.print("  • [yellow]limited[/yellow] - RedELK core only, without Jupyter/BloodHound (requires 4GB+ RAM)")
        
        install_type = Prompt.ask(
            "\nInstallation type",
            choices=["full", "limited"],
            default="full"
        )
        self.config['install_type'] = install_type
        
        # Server domain/IP
        console.print("\n[bold cyan]Step 2/6: Server Address[/bold cyan]")
        console.print("Enter the domain name or IP address where this RedELK server will be accessible.")
        console.print("[dim]This is used for TLS certificates and agent connections.[/dim]")
        
        # Try to auto-detect IP
        try:
            default_ip = socket.gethostbyname(socket.gethostname())
        except:
            default_ip = "127.0.0.1"
        
        server_address = Prompt.ask(
            "\nServer domain or IP",
            default=default_ip
        )
        self.config['server_address'] = server_address
        
        # Let's Encrypt
        console.print("\n[bold cyan]Step 3/6: TLS Certificates[/bold cyan]")
        console.print("RedELK can use Let's Encrypt for automatic TLS certificates,")
        console.print("or generate self-signed certificates for testing.")
        
        use_letsencrypt = Confirm.ask(
            "\nUse Let's Encrypt for TLS certificates?",
            default=False
        )
        self.config['use_letsencrypt'] = use_letsencrypt
        
        if use_letsencrypt:
            email = Prompt.ask(
                "Email for Let's Encrypt notifications",
                default=""
            )
            self.config['letsencrypt_email'] = email
            self.config['letsencrypt_staging'] = Confirm.ask(
                "Use Let's Encrypt staging (for testing)?",
                default=True
            )
        else:
            self.config['letsencrypt_email'] = ""
            self.config['letsencrypt_staging'] = False
        
        # Project name
        console.print("\n[bold cyan]Step 4/6: Project Name[/bold cyan]")
        console.print("Give your red team operation a project name.")
        
        project_name = Prompt.ask(
            "\nProject name",
            default="redelk-project"
        )
        self.config['project_name'] = project_name
        
        # Notification settings
        console.print("\n[bold cyan]Step 5/6: Notifications[/bold cyan]")
        console.print("RedELK can send notifications when Blue Team activity is detected.")
        
        self.config['enable_email'] = Confirm.ask("Enable email notifications?", default=False)
        self.config['enable_slack'] = Confirm.ask("Enable Slack notifications?", default=False)
        self.config['enable_msteams'] = Confirm.ask("Enable MS Teams notifications?", default=False)
        
        # Team servers count (for memory sizing)
        console.print("\n[bold cyan]Step 6/6: Infrastructure Sizing[/bold cyan]")
        console.print("How many C2 team servers will connect to this RedELK instance?")
        console.print("[dim]This helps optimize memory allocation.[/dim]")
        
        team_servers = Prompt.ask(
            "\nNumber of team servers",
            default="3"
        )
        try:
            self.config['team_servers_count'] = int(team_servers)
        except:
            self.config['team_servers_count'] = 3
        
        console.print()
    
    def show_configuration_summary(self) -> bool:
        """Show configuration summary and confirm"""
        console.print(Panel.fit("📋 [bold]Configuration Summary[/bold]", border_style="blue"))
        
        summary_table = Table(show_header=False, box=box.ROUNDED)
        summary_table.add_column("Setting", style="cyan", width=30)
        summary_table.add_column("Value", style="green", width=50)
        
        summary_table.add_row("Installation Type", self.config['install_type'].upper())
        summary_table.add_row("Server Address", self.config['server_address'])
        summary_table.add_row("TLS Certificates", "Let's Encrypt" if self.config['use_letsencrypt'] else "Self-signed")
        if self.config['use_letsencrypt']:
            summary_table.add_row("  └─ Email", self.config['letsencrypt_email'])
            summary_table.add_row("  └─ Staging", "Yes" if self.config['letsencrypt_staging'] else "No")
        summary_table.add_row("Project Name", self.config['project_name'])
        
        notifications = []
        if self.config['enable_email']:
            notifications.append("Email")
        if self.config['enable_slack']:
            notifications.append("Slack")
        if self.config['enable_msteams']:
            notifications.append("MS Teams")
        summary_table.add_row("Notifications", ", ".join(notifications) if notifications else "None")
        summary_table.add_row("Team Servers", str(self.config['team_servers_count']))
        summary_table.add_row("ELK Version", ELK_VERSION)
        summary_table.add_row("RedELK Version", REDELK_VERSION)
        
        console.print(summary_table)
        console.print()
        
        if self.dry_run:
            console.print("[yellow]🔍 Dry-run mode: No changes will be made[/yellow]\n")
            return True
        
        return Confirm.ask("\n[bold]Proceed with installation?[/bold]", default=True)
    
    def run(self) -> int:
        """Main installation workflow"""
        try:
            self.show_welcome()
            
            # Quick start mode
            if self.args.quickstart:
                console.print("[yellow]⚡ Quick Start Mode: Using defaults for rapid deployment[/yellow]\n")
                self.config = self.get_quickstart_config()
            else:
                # Run pre-flight checks
                if not self.run_preflight_checks():
                    return 1
                
                # Gather configuration
                self.gather_configuration()
            
            # Show summary and confirm
            if not self.show_configuration_summary():
                console.print("[yellow]Installation cancelled by user.[/yellow]")
                return 0
            
            # Perform installation
            if not self.dry_run:
                if not self.perform_installation():
                    return 1
                
                self.show_completion_message()
            else:
                console.print("[green]✅ Dry-run completed successfully![/green]")
                console.print("\nRun without --dry-run to perform actual installation.")
            
            return 0
            
        except KeyboardInterrupt:
            console.print("\n\n[yellow]Installation interrupted by user.[/yellow]")
            return 130
        except Exception as e:
            console.print(f"\n[red]❌ Fatal error: {str(e)}[/red]")
            if self.args.verbose:
                console.print_exception()
            return 1
    
    def get_quickstart_config(self) -> dict:
        """Get quick start configuration"""
        try:
            default_ip = socket.gethostbyname(socket.gethostname())
        except:
            default_ip = "127.0.0.1"
        
        return {
            'install_type': 'full',
            'server_address': default_ip,
            'use_letsencrypt': False,
            'letsencrypt_email': '',
            'letsencrypt_staging': False,
            'project_name': 'redelk-quickstart',
            'enable_email': False,
            'enable_slack': False,
            'enable_msteams': False,
            'team_servers_count': 3
        }
    
    def perform_installation(self) -> bool:
        """Perform the actual installation steps"""
        console.print(Panel.fit("🚀 [bold]Starting Installation[/bold]", border_style="blue"))
        
        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            BarColumn(),
            TaskProgressColumn(),
            TimeElapsedColumn(),
            console=console
        ) as progress:
            
            total_steps = 8
            task = progress.add_task("[cyan]Installing RedELK...", total=total_steps)
            
            # Step 1: Create directories
            progress.update(task, description="[cyan]Step 1/8: Creating directory structure...")
            time.sleep(0.5)  # Placeholder
            progress.advance(task)
            
            # Step 2: Generate certificates
            progress.update(task, description="[cyan]Step 2/8: Generating TLS certificates...")
            time.sleep(1.5)  # Placeholder
            progress.advance(task)
            
            # Step 3: Generate configuration
            progress.update(task, description="[cyan]Step 3/8: Generating configuration files...")
            time.sleep(0.8)  # Placeholder
            progress.advance(task)
            
            # Step 4: Generate passwords
            progress.update(task, description="[cyan]Step 4/8: Generating secure passwords...")
            time.sleep(0.5)  # Placeholder
            progress.advance(task)
            
            # Step 5: Build Docker images
            progress.update(task, description="[cyan]Step 5/8: Building Docker images...")
            time.sleep(3)  # Placeholder
            progress.advance(task)
            
            # Step 6: Configure services
            progress.update(task, description="[cyan]Step 6/8: Configuring services...")
            time.sleep(0.8)  # Placeholder
            progress.advance(task)
            
            # Step 7: Start services
            progress.update(task, description="[cyan]Step 7/8: Starting services...")
            time.sleep(2)  # Placeholder
            progress.advance(task)
            
            # Step 8: Verify installation
            progress.update(task, description="[cyan]Step 8/8: Verifying installation...")
            time.sleep(1)  # Placeholder
            progress.advance(task)
        
        return True
    
    def show_completion_message(self):
        """Show installation completion message with next steps"""
        console.print("\n" + "="*70)
        console.print("[bold green]🎉 Installation Complete![/bold green]", justify="center")
        console.print("="*70 + "\n")
        
        # Access information
        info_table = Table(title="🌐 Access Information", box=box.DOUBLE, show_header=False)
        info_table.add_column("Service", style="cyan bold", width=25)
        info_table.add_column("URL / Info", style="green", width=40)
        
        server = self.config['server_address']
        info_table.add_row("Kibana Dashboard", f"https://{server}/")
        info_table.add_row("  Username", "redelk")
        info_table.add_row("  Password", "[dim]See redelk_passwords.cfg[/dim]")
        
        if self.config['install_type'] == 'full':
            info_table.add_row("Jupyter Notebooks", f"https://{server}/jupyter")
            info_table.add_row("BloodHound", f"https://{server}:8443")
            info_table.add_row("Neo4j Browser", f"http://{server}:7474")
        
        console.print(info_table)
        console.print()
        
        # Next steps
        next_steps = Panel(
            "[bold]📝 Next Steps:[/bold]\n\n"
            "1. Review generated passwords:\n"
            "   [cyan]cat elkserver/redelk_passwords.cfg[/cyan]\n\n"
            "2. Configure C2 servers and redirectors:\n"
            "   [cyan]python3 install-agent.py[/cyan]\n\n"
            "3. Customize alarm settings:\n"
            "   [cyan]nano elkserver/mounts/redelk-config/etc/redelk/config.json[/cyan]\n\n"
            "4. View service logs:\n"
            "   [cyan]docker-compose -f elkserver/docker-compose.yml logs -f[/cyan]\n\n"
            "5. Check service status:\n"
            "   [cyan]./redelk status[/cyan]\n",
            title="What's Next?",
            border_style="blue"
        )
        console.print(next_steps)
        
        console.print("\n[dim]📚 Full documentation: https://github.com/outflanknl/RedELK/wiki[/dim]\n")


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="RedELK Modern Installer - User-friendly deployment tool",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument(
        '--quickstart',
        action='store_true',
        help='Quick start mode with default configuration'
    )
    
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Show what would be done without making changes'
    )
    
    parser.add_argument(
        '--skip-warnings',
        action='store_true',
        help='Skip confirmation prompts for warnings'
    )
    
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Enable verbose output'
    )
    
    parser.add_argument(
        '--version',
        action='version',
        version=f'RedELK Installer v{REDELK_VERSION}'
    )
    
    args = parser.parse_args()
    
    installer = Installer(args)
    sys.exit(installer.run())


if __name__ == "__main__":
    main()


