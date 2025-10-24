#!/usr/bin/env python3
"""
RedELK Certificate Generator
Version 3.0.0

Automatically generates TLS certificates for RedELK deployment.
Simplifies the certificate generation process from the original bash script.
"""

import os
import sys
import subprocess
import socket
from pathlib import Path
import argparse

try:
    from rich.console import Console
    from rich.prompt import Prompt, Confirm
    from rich.panel import Panel
except ImportError:
    print("📦 Installing required dependencies...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "rich>=13.0.0"])
    from rich.console import Console
    from rich.prompt import Prompt, Confirm
    from rich.panel import Panel

console = Console()

class CertificateGenerator:
    """Certificate generator for RedELK"""
    
    def __init__(self, args):
        self.args = args
        self.base_dir = Path(__file__).parent.parent
        self.certs_dir = self.base_dir / "certs"
        self.config = {}
        
    def show_welcome(self):
        """Display welcome message"""
        console.print("\n[bold cyan]🔐 RedELK Certificate Generator[/bold cyan]\n")
        console.print("This tool will generate TLS certificates for your RedELK deployment.\n")
    
    def gather_configuration(self):
        """Gather certificate configuration"""
        console.print(Panel.fit("⚙️  [bold]Certificate Configuration[/bold]", border_style="blue"))
        console.print()
        
        # Get server address
        console.print("[bold cyan]Server Address[/bold cyan]")
        console.print("Enter the IP address or domain name where RedELK will be accessible.")
        console.print("[dim]This is used in the certificate's Subject Alternative Name (SAN).[/dim]\n")
        
        # Try to auto-detect
        try:
            default_ip = socket.gethostbyname(socket.gethostname())
        except:
            default_ip = "127.0.0.1"
        
        server_address = Prompt.ask(
            "Server IP or domain",
            default=default_ip
        )
        
        # Check if it's an IP or domain
        self.config['is_ip'] = self.is_ip_address(server_address)
        self.config['server_address'] = server_address
        
        # Organization details
        console.print("\n[bold cyan]Organization Details[/bold cyan]")
        console.print("[dim]These details will be included in the certificate.[/dim]\n")
        
        self.config['country'] = Prompt.ask("Country (2 letters)", default="US")
        self.config['state'] = Prompt.ask("State/Province", default="State")
        self.config['city'] = Prompt.ask("City", default="City")
        self.config['org'] = Prompt.ask("Organization", default="RedTeam")
        self.config['org_unit'] = Prompt.ask("Organizational Unit", default="Operations")
        self.config['email'] = Prompt.ask("Email", default="admin@example.com")
        
        # Additional names (optional)
        console.print("\n[bold cyan]Additional Names (Optional)[/bold cyan]")
        console.print("You can add additional DNS names or IP addresses to the certificate.\n")
        
        if Confirm.ask("Add additional DNS names or IPs?", default=False):
            additional = Prompt.ask("Enter additional names (comma-separated)")
            self.config['additional'] = [name.strip() for name in additional.split(',') if name.strip()]
        else:
            self.config['additional'] = []
        
        console.print()
    
    def is_ip_address(self, address: str) -> bool:
        """Check if string is an IP address"""
        try:
            socket.inet_aton(address)
            return True
        except socket.error:
            return False
    
    def generate_openssl_config(self) -> str:
        """Generate OpenSSL configuration"""
        san_entries = []
        dns_count = 1
        ip_count = 1
        
        # Add main address
        if self.config['is_ip']:
            san_entries.append(f"IP.{ip_count} = {self.config['server_address']}")
            ip_count += 1
        else:
            san_entries.append(f"DNS.{dns_count} = {self.config['server_address']}")
            dns_count += 1
        
        # Add additional names
        for additional in self.config['additional']:
            if self.is_ip_address(additional):
                san_entries.append(f"IP.{ip_count} = {additional}")
                ip_count += 1
            else:
                san_entries.append(f"DNS.{dns_count} = {additional}")
                dns_count += 1
        
        # Add localhost
        san_entries.append(f"DNS.{dns_count} = localhost")
        san_entries.append(f"IP.{ip_count} = 127.0.0.1")
        
        san_section = "\n".join(san_entries)
        
        config = f"""[req]
distinguished_name = req_distinguished_name
x509_extensions = v3_req
prompt = no

[req_distinguished_name]
C = {self.config['country']}
ST = {self.config['state']}
L = {self.config['city']}
O = {self.config['org']}
OU = {self.config['org_unit']}
CN = {self.config['server_address']}
emailAddress = {self.config['email']}

[v3_ca]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer:always
basicConstraints = CA:TRUE

[v3_req]
keyUsage = nonRepudiation, digitalSignature, keyEncipherment, dataEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
{san_section}
"""
        return config
    
    def generate_certificates(self) -> bool:
        """Generate all certificates"""
        console.print(Panel.fit("🔨 [bold]Generating Certificates[/bold]", border_style="blue"))
        
        try:
            # Create certs directory
            self.certs_dir.mkdir(exist_ok=True)
            
            # Write OpenSSL config
            config_file = self.certs_dir / "config.cnf"
            with open(config_file, "w") as f:
                f.write(self.generate_openssl_config())
            
            console.print("[cyan]📝 Generated OpenSSL configuration[/cyan]")
            
            # Generate CA private key
            console.print("[cyan]🔑 Generating CA private key...[/cyan]")
            subprocess.run([
                "openssl", "genrsa",
                "-out", str(self.certs_dir / "redelkCA.key"),
                "2048"
            ], check=True, capture_output=True)
            
            # Generate CA certificate
            console.print("[cyan]📜 Generating CA certificate...[/cyan]")
            subprocess.run([
                "openssl", "req", "-new", "-x509",
                "-days", "3650",
                "-key", str(self.certs_dir / "redelkCA.key"),
                "-out", str(self.certs_dir / "redelkCA.crt"),
                "-extensions", "v3_ca",
                "-config", str(config_file)
            ], check=True, capture_output=True)
            
            # Generate server private key
            console.print("[cyan]🔑 Generating server private key...[/cyan]")
            subprocess.run([
                "openssl", "genrsa",
                "-out", str(self.certs_dir / "elkserver.key"),
                "2048"
            ], check=True, capture_output=True)
            
            # Generate server CSR
            console.print("[cyan]📄 Generating server certificate request...[/cyan]")
            subprocess.run([
                "openssl", "req", "-new",
                "-key", str(self.certs_dir / "elkserver.key"),
                "-out", str(self.certs_dir / "elkserver.csr"),
                "-config", str(config_file)
            ], check=True, capture_output=True)
            
            # Sign server certificate
            console.print("[cyan]✍️  Signing server certificate...[/cyan]")
            subprocess.run([
                "openssl", "x509", "-req",
                "-days", "3650",
                "-in", str(self.certs_dir / "elkserver.csr"),
                "-CA", str(self.certs_dir / "redelkCA.crt"),
                "-CAkey", str(self.certs_dir / "redelkCA.key"),
                "-CAcreateserial",
                "-out", str(self.certs_dir / "elkserver.crt"),
                "-extensions", "v3_req",
                "-extfile", str(config_file)
            ], check=True, capture_output=True)
            
            # Convert to PKCS8
            console.print("[cyan]🔄 Converting to PKCS8 format...[/cyan]")
            subprocess.run([
                "cp", str(self.certs_dir / "elkserver.key"),
                str(self.certs_dir / "elkserver.key.pem")
            ], check=True)
            
            subprocess.run([
                "openssl", "pkcs8",
                "-in", str(self.certs_dir / "elkserver.key.pem"),
                "-topk8", "-nocrypt",
                "-out", str(self.certs_dir / "elkserver.key")
            ], check=True, capture_output=True)
            
            console.print("[green]✅ All certificates generated successfully![/green]")
            return True
            
        except subprocess.CalledProcessError as e:
            console.print(f"[red]❌ Failed to generate certificates: {e}[/red]")
            return False
        except Exception as e:
            console.print(f"[red]❌ Error: {e}[/red]")
            return False
    
    def copy_certificates(self) -> bool:
        """Copy certificates to appropriate locations"""
        console.print("\n[cyan]📂 Copying certificates to deployment locations...[/cyan]")
        
        try:
            # Create directories if they don't exist
            logstash_certs = self.base_dir / "elkserver" / "mounts" / "logstash-config" / "certs_inputs"
            logstash_certs.mkdir(parents=True, exist_ok=True)
            
            c2_certs = self.base_dir / "c2servers" / "filebeat"
            c2_certs.mkdir(parents=True, exist_ok=True)
            
            redir_certs = self.base_dir / "redirs" / "filebeat"
            redir_certs.mkdir(parents=True, exist_ok=True)
            
            # Copy all certs to logstash
            subprocess.run([
                "cp", "-r",
                str(self.certs_dir / "*"),
                str(logstash_certs)
            ], shell=True, check=False)
            
            # Copy CA to agents
            subprocess.run([
                "cp",
                str(self.certs_dir / "redelkCA.crt"),
                str(c2_certs)
            ], check=True)
            
            subprocess.run([
                "cp",
                str(self.certs_dir / "redelkCA.crt"),
                str(redir_certs)
            ], check=True)
            
            console.print("[green]✅ Certificates copied successfully![/green]")
            return True
            
        except Exception as e:
            console.print(f"[yellow]⚠️  Warning: Could not copy all certificates: {e}[/yellow]")
            return True  # Don't fail on this
    
    def show_completion_message(self):
        """Show completion message"""
        console.print("\n" + "="*70)
        console.print("[bold green]🎉 Certificate Generation Complete![/bold green]", justify="center")
        console.print("="*70 + "\n")
        
        console.print("[bold]Generated Files:[/bold]")
        console.print(f"  • [cyan]{self.certs_dir}/redelkCA.crt[/cyan]      - Certificate Authority")
        console.print(f"  • [cyan]{self.certs_dir}/redelkCA.key[/cyan]      - CA Private Key")
        console.print(f"  • [cyan]{self.certs_dir}/elkserver.crt[/cyan]     - Server Certificate")
        console.print(f"  • [cyan]{self.certs_dir}/elkserver.key[/cyan]     - Server Private Key")
        console.print(f"  • [cyan]{self.certs_dir}/config.cnf[/cyan]        - OpenSSL Configuration")
        
        console.print("\n[bold]Next Steps:[/bold]")
        console.print("  1. Certificates are ready for RedELK deployment")
        console.print("  2. Run the main installer: [cyan]sudo python3 install.py[/cyan]")
        console.print("  3. Copy [cyan]redelkCA.crt[/cyan] to your C2 servers and redirectors\n")
    
    def run(self) -> int:
        """Main execution"""
        try:
            self.show_welcome()
            
            if not self.args.auto:
                self.gather_configuration()
            else:
                # Auto mode: use defaults
                try:
                    default_ip = socket.gethostbyname(socket.gethostname())
                except:
                    default_ip = "127.0.0.1"
                
                self.config = {
                    'is_ip': True,
                    'server_address': default_ip,
                    'country': 'US',
                    'state': 'State',
                    'city': 'City',
                    'org': 'RedTeam',
                    'org_unit': 'Operations',
                    'email': 'admin@example.com',
                    'additional': []
                }
                console.print(f"[yellow]🤖 Auto mode: Using detected IP {default_ip}[/yellow]\n")
            
            if not self.generate_certificates():
                return 1
            
            self.copy_certificates()
            self.show_completion_message()
            
            return 0
            
        except KeyboardInterrupt:
            console.print("\n\n[yellow]Certificate generation cancelled.[/yellow]")
            return 130
        except Exception as e:
            console.print(f"\n[red]❌ Fatal error: {str(e)}[/red]")
            if self.args.verbose:
                import traceback
                traceback.print_exc()
            return 1


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description="RedELK Certificate Generator - Auto-generate TLS certificates",
        formatter_class=argparse.RawDescriptionHelpFormatter
    )
    
    parser.add_argument(
        '--auto',
        action='store_true',
        help='Automatic mode with default values'
    )
    
    parser.add_argument(
        '-v', '--verbose',
        action='store_true',
        help='Enable verbose output'
    )
    
    parser.add_argument(
        '--version',
        action='version',
        version='RedELK Certificate Generator v3.0.0'
    )
    
    args = parser.parse_args()
    
    generator = CertificateGenerator(args)
    sys.exit(generator.run())


if __name__ == "__main__":
    main()


