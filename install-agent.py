#!/usr/bin/env python3
"""
RedELK Agent Installer
Version 3.0.0

Simplified installer for RedELK agents on C2 servers and redirectors.
Replaces install-c2server.sh and install-redir.sh with a unified, user-friendly installer.
"""

import os
import sys
import subprocess
import socket
import argparse
from pathlib import Path
from typing import Dict

# Check Python version
if sys.version_info < (3, 8):
    print("❌ Error: RedELK agent installer requires Python 3.8 or higher")
    sys.exit(1)

# Try to import required packages
try:
    from rich.console import Console
    from rich.prompt import Prompt, Confirm
    from rich.progress import Progress, SpinnerColumn, TextColumn
    from rich.panel import Panel
    from rich.table import Table
    from rich import box
except ImportError:
    print("📦 Installing required dependencies...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "rich>=13.0.0"])
    from rich.console import Console
    from rich.prompt import Prompt, Confirm
    from rich.progress import Progress, SpinnerColumn, TextColumn
    from rich.panel import Panel
    from rich.table import Table
    from rich import box

console = Console()

# Constants
ELK_VERSION = "8.11.3"
AGENT_VERSION = "3.0.0"


class AgentInstaller:
    """Agent installer for C2 servers and redirectors"""
    
    def __init__(self, args):
        self.args = args
        self.config = {}
        self.agent_type = None
        
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
    ║              Agent Installer v3.0.0                       ║
    ║                                                           ║
    ╚═══════════════════════════════════════════════════════════╝
        """
        console.print(welcome, style="bold cyan")
        console.print("\n[bold]RedELK Agent Installation Wizard[/bold]\n")
        console.print("This installer will configure this machine to send logs to your RedELK server.\n")
    
    def check_prerequisites(self) -> bool:
        """Check if prerequisites are met"""
        console.print(Panel.fit("🔍 [bold]Checking Prerequisites[/bold]", border_style="blue"))
        
        checks = []
        
        # Root check
        if os.geteuid() == 0:
            checks.append(("✓ Root privileges", "[green]PASS[/green]"))
        else:
            checks.append(("✗ Root privileges", "[red]FAIL[/red]"))
            console.print("[red]❌ This installer must be run as root.[/red]")
            console.print("[yellow]💡 Tip: Run with sudo:[/yellow]")
            console.print(f"   sudo python3 {sys.argv[0]}\n")
            return False
        
        # OS check
        if os.path.exists("/etc/debian_version"):
            checks.append(("✓ Debian/Ubuntu OS", "[green]PASS[/green]"))
        else:
            checks.append(("✗ Debian/Ubuntu OS", "[red]FAIL[/red]"))
            console.print("[red]❌ This installer only supports Debian/Ubuntu-based systems.[/red]\n")
            return False
        
        # Display checks
        table = Table(show_header=False, box=box.ROUNDED)
        table.add_column("Check", style="cyan", width=30)
        table.add_column("Status", width=15)
        
        for check, status in checks:
            table.add_row(check, status)
        
        console.print(table)
        console.print()
        return True
    
    def gather_configuration(self):
        """Interactively gather configuration"""
        console.print(Panel.fit("⚙️  [bold]Configuration Setup[/bold]", border_style="blue"))
        console.print()
        
        # Agent type
        console.print("[bold cyan]Step 1/5: Agent Type[/bold cyan]")
        console.print("What type of agent is this?")
        console.print("  • [green]c2[/green]         - Command & Control server (Cobalt Strike, Sliver, PoshC2, etc.)")
        console.print("  • [yellow]redirector[/yellow]  - Traffic redirector (Apache, HAProxy, Nginx)")
        
        self.agent_type = Prompt.ask(
            "\nAgent type",
            choices=["c2", "redirector"],
            default="c2"
        )
        
        # Hostname
        console.print("\n[bold cyan]Step 2/5: Hostname[/bold cyan]")
        console.print("Enter a unique identifier for this agent.")
        console.print("[dim]This helps identify logs from this system in RedELK.[/dim]")
        
        try:
            default_hostname = socket.gethostname()
        except:
            default_hostname = "unknown"
        
        self.config['hostname'] = Prompt.ask(
            "\nHostname/Identifier",
            default=default_hostname
        )
        
        # Attack scenario
        console.print("\n[bold cyan]Step 3/5: Attack Scenario[/bold cyan]")
        console.print("Enter the name of your red team operation/scenario.")
        console.print("[dim]All agents in the same operation should use the same scenario name.[/dim]")
        
        self.config['attack_scenario'] = Prompt.ask(
            "\nAttack scenario",
            default="operation-redteam"
        )
        
        # RedELK server
        console.print("\n[bold cyan]Step 4/5: RedELK Server[/bold cyan]")
        console.print("Enter the IP address or hostname of your RedELK server.")
        
        self.config['redelk_server'] = Prompt.ask(
            "\nRedELK server IP/hostname"
        )
        
        # Port
        console.print("\n[bold cyan]Step 5/5: Logstash Port[/bold cyan]")
        console.print("Enter the port where Logstash is listening (usually 5044).")
        
        self.config['logstash_port'] = Prompt.ask(
            "\nLogstash port",
            default="5044"
        )
        
        console.print()
    
    def show_configuration_summary(self) -> bool:
        """Show configuration summary and confirm"""
        console.print(Panel.fit("📋 [bold]Configuration Summary[/bold]", border_style="blue"))
        
        table = Table(show_header=False, box=box.ROUNDED)
        table.add_column("Setting", style="cyan", width=25)
        table.add_column("Value", style="green", width=40)
        
        table.add_row("Agent Type", self.agent_type.upper())
        table.add_row("Hostname", self.config['hostname'])
        table.add_row("Attack Scenario", self.config['attack_scenario'])
        table.add_row("RedELK Server", self.config['redelk_server'])
        table.add_row("Logstash Port", self.config['logstash_port'])
        table.add_row("Filebeat Version", ELK_VERSION)
        
        console.print(table)
        console.print()
        
        return Confirm.ask("\n[bold]Proceed with installation?[/bold]", default=True)
    
    def install_filebeat(self) -> bool:
        """Install Filebeat"""
        console.print("[cyan]📦 Installing Filebeat...[/cyan]")
        
        try:
            # Add GPG key
            subprocess.run([
                "wget", "-qO", "-", "https://artifacts.elastic.co/GPG-KEY-elasticsearch"
            ], stdout=subprocess.PIPE, check=True)
            
            subprocess.run([
                "apt-key", "add", "-"
            ], stdin=subprocess.PIPE, check=True)
            
            # Add repository
            if not os.path.exists("/etc/apt/sources.list.d/elastic-8.x.list"):
                with open("/etc/apt/sources.list.d/elastic-8.x.list", "w") as f:
                    f.write("deb https://artifacts.elastic.co/packages/8.x/apt stable main\n")
            
            # Update and install
            subprocess.run(["apt-get", "update", "-qq"], check=True)
            subprocess.run(["apt-get", "install", "-y", "-qq", f"filebeat={ELK_VERSION}"], check=True)
            subprocess.run(["systemctl", "enable", "filebeat"], check=True)
            
            console.print("[green]✅ Filebeat installed successfully[/green]")
            return True
            
        except subprocess.CalledProcessError as e:
            console.print(f"[red]❌ Failed to install Filebeat: {e}[/red]")
            return False
    
    def configure_filebeat(self) -> bool:
        """Configure Filebeat"""
        console.print("[cyan]⚙️  Configuring Filebeat...[/cyan]")
        
        try:
            # Backup original config
            if os.path.exists("/etc/filebeat/filebeat.yml") and not os.path.exists("/etc/filebeat/filebeat.yml.orig"):
                os.rename("/etc/filebeat/filebeat.yml", "/etc/filebeat/filebeat.yml.orig")
            
            # Create configuration based on agent type
            config_content = self.generate_filebeat_config()
            
            with open("/etc/filebeat/filebeat.yml", "w") as f:
                f.write(config_content)
            
            # Copy CA certificate if available
            if os.path.exists("./filebeat/redelkCA.crt"):
                os.makedirs("/etc/filebeat", exist_ok=True)
                subprocess.run(["cp", "./filebeat/redelkCA.crt", "/etc/filebeat/"], check=True)
                console.print("[green]✅ CA certificate installed[/green]")
            else:
                console.print("[yellow]⚠️  CA certificate not found. You'll need to copy it manually.[/yellow]")
                console.print("[yellow]   Expected location: ./filebeat/redelkCA.crt[/yellow]")
            
            console.print("[green]✅ Filebeat configured successfully[/green]")
            return True
            
        except Exception as e:
            console.print(f"[red]❌ Failed to configure Filebeat: {e}[/red]")
            return False
    
    def generate_filebeat_config(self) -> str:
        """Generate Filebeat configuration"""
        if self.agent_type == "c2":
            return f"""# RedELK Filebeat Configuration - C2 Server
# Generated by RedELK Agent Installer v{AGENT_VERSION}

filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/cobaltstrike/*.log
    - /opt/cobaltstrike/logs/*.log
  fields:
    infra: {self.config['hostname']}
    c2type: cobaltstrike
    attackscenario: {self.config['attack_scenario']}

- type: log
  enabled: true
  paths:
    - /var/log/sliver/*.log
    - ~/.sliver/logs/*.log
  fields:
    infra: {self.config['hostname']}
    c2type: sliver
    attackscenario: {self.config['attack_scenario']}

output.logstash:
  hosts: ["{self.config['redelk_server']}:{self.config['logstash_port']}"]
  ssl.certificate_authorities: ["/etc/filebeat/redelkCA.crt"]
  ssl.verification_mode: certificate

logging.level: info
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  name: filebeat
  keepfiles: 7
  permissions: 0644
"""
        else:  # redirector
            return f"""# RedELK Filebeat Configuration - Redirector
# Generated by RedELK Agent Installer v{AGENT_VERSION}

filebeat.inputs:
- type: log
  enabled: true
  paths:
    - /var/log/apache2/access*.log
    - /var/log/apache2/ssl_access*.log
  fields:
    infra: {self.config['hostname']}
    redirtype: apache
    attackscenario: {self.config['attack_scenario']}

- type: log
  enabled: true
  paths:
    - /var/log/nginx/access*.log
  fields:
    infra: {self.config['hostname']}
    redirtype: nginx
    attackscenario: {self.config['attack_scenario']}

- type: log
  enabled: true
  paths:
    - /var/log/haproxy.log
  fields:
    infra: {self.config['hostname']}
    redirtype: haproxy
    attackscenario: {self.config['attack_scenario']}

output.logstash:
  hosts: ["{self.config['redelk_server']}:{self.config['logstash_port']}"]
  ssl.certificate_authorities: ["/etc/filebeat/redelkCA.crt"]
  ssl.verification_mode: certificate

logging.level: info
logging.to_files: true
logging.files:
  path: /var/log/filebeat
  name: filebeat
  keepfiles: 7
  permissions: 0644
"""
    
    def start_filebeat(self) -> bool:
        """Start Filebeat service"""
        console.print("[cyan]🚀 Starting Filebeat...[/cyan]")
        
        try:
            subprocess.run(["systemctl", "restart", "filebeat"], check=True)
            subprocess.run(["systemctl", "status", "filebeat", "--no-pager"], check=True)
            
            console.print("[green]✅ Filebeat started successfully[/green]")
            return True
            
        except subprocess.CalledProcessError as e:
            console.print(f"[red]❌ Failed to start Filebeat: {e}[/red]")
            return False
    
    def test_connection(self) -> bool:
        """Test connection to RedELK server"""
        console.print("[cyan]🔍 Testing connection to RedELK server...[/cyan]")
        
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(5)
            result = sock.connect_ex((self.config['redelk_server'], int(self.config['logstash_port'])))
            sock.close()
            
            if result == 0:
                console.print(f"[green]✅ Successfully connected to {self.config['redelk_server']}:{self.config['logstash_port']}[/green]")
                return True
            else:
                console.print(f"[yellow]⚠️  Could not connect to {self.config['redelk_server']}:{self.config['logstash_port']}[/yellow]")
                console.print("[yellow]   This might be a firewall issue or the RedELK server might not be running.[/yellow]")
                return False
                
        except Exception as e:
            console.print(f"[yellow]⚠️  Connection test failed: {e}[/yellow]")
            return False
    
    def show_completion_message(self):
        """Show completion message"""
        console.print("\n" + "="*70)
        console.print("[bold green]🎉 Agent Installation Complete![/bold green]", justify="center")
        console.print("="*70 + "\n")
        
        info_table = Table(title="📋 Installation Summary", box=box.DOUBLE, show_header=False)
        info_table.add_column("Item", style="cyan bold", width=25)
        info_table.add_column("Details", style="green", width=40)
        
        info_table.add_row("Agent Type", self.agent_type.upper())
        info_table.add_row("Hostname", self.config['hostname'])
        info_table.add_row("RedELK Server", f"{self.config['redelk_server']}:{self.config['logstash_port']}")
        info_table.add_row("Filebeat Status", "Running")
        info_table.add_row("Config File", "/etc/filebeat/filebeat.yml")
        
        console.print(info_table)
        console.print()
        
        next_steps = Panel(
            "[bold]📝 Next Steps:[/bold]\n\n"
            "1. Verify logs are reaching RedELK:\n"
            "   [cyan]tail -f /var/log/filebeat/filebeat[/cyan]\n\n"
            "2. Check Filebeat status:\n"
            "   [cyan]systemctl status filebeat[/cyan]\n\n"
            "3. View logs in RedELK Kibana dashboard\n\n"
            "4. If no connection, check:\n"
            "   • Firewall allows port 5044\n"
            "   • CA certificate is correct\n"
            "   • RedELK server is reachable\n",
            title="What's Next?",
            border_style="blue"
        )
        console.print(next_steps)
        
        console.print("\n[dim]📚 Documentation: https://github.com/outflanknl/RedELK/wiki[/dim]\n")
    
    def run(self) -> int:
        """Main installation workflow"""
        try:
            self.show_welcome()
            
            # Prerequisites
            if not self.check_prerequisites():
                return 1
            
            # Gather configuration
            self.gather_configuration()
            
            # Show summary
            if not self.show_configuration_summary():
                console.print("[yellow]Installation cancelled by user.[/yellow]")
                return 0
            
            # Install and configure
            console.print(Panel.fit("🚀 [bold]Starting Installation[/bold]", border_style="blue"))
            
            if not self.install_filebeat():
                return 1
            
            if not self.configure_filebeat():
                return 1
            
            if not self.start_filebeat():
                return 1
            
            # Test connection
            self.test_connection()
            
            # Show completion
            self.show_completion_message()
            
            return 0
            
        except KeyboardInterrupt:
            console.print("\n\n[yellow]Installation interrupted by user.[/yellow]")
            return 130
        except Exception as e:
            console.print(f"\n[red]❌ Fatal error: {str(e)}[/red]")
            if self.args.verbose:
                console.print_exception()
            return 1


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="RedELK Agent Installer - Deploy agents to C2 servers and redirectors",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Enable verbose output'
    )
    
    parser.add_argument(
        '--version',
        action='version',
        version=f'RedELK Agent Installer v{AGENT_VERSION}'
    )
    
    args = parser.parse_args()
    
    installer = AgentInstaller(args)
    sys.exit(installer.run())


if __name__ == "__main__":
    main()


