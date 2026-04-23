# outputs.tf - Output values after deployment

locals {
  deployment_info_content = <<-EOT

  +---------------------------------------------------------------------+
  | 1. GUACAMOLE ACCESS PORTAL                                          |
  +---------------------------------------------------------------------+
    URL:          https://${aws_eip.guacamole.public_ip}/guacamole
    Public IP:    ${aws_eip.guacamole.public_ip}
    Private IP:   ${aws_network_interface.guacamole.private_ip}
    UI Username:  guacadmin
    UI Password:  ${nonsensitive(random_password.lab.result)}
    SSH Username: admin
    SSH Password: ${nonsensitive(random_password.lab.result)}
    SSH (external): ssh -i ${var.ssh_key_name}.pem admin@${aws_eip.guacamole.public_ip}
    SSH (internal): ssh admin@${aws_network_interface.guacamole.private_ip}

  +---------------------------------------------------------------------+
  | 2. MYTHIC C2 TEAM SERVER                                            |
  +---------------------------------------------------------------------+
    Web UI:       https://mythic:7443  (access via WinOp workstation)
    Private IP:   ${aws_network_interface.mythic.private_ip}
    SSH Username: admin
    SSH Password: ${nonsensitive(random_password.lab.result)}
    SSH (internal): ssh admin@${aws_network_interface.mythic.private_ip}
    UI Username:  mythic_admin
    UI Password:  ${nonsensitive(random_password.lab.result)}
    Operator:     Port 7443 (Web UI via Windows/Guacamole)
    Guacamole:    Mythic C2 Server (SSH)

  +---------------------------------------------------------------------+
  | 3. SLIVER C2 SERVER                                                 |
  +---------------------------------------------------------------------+
    Private IP:   ${aws_network_interface.sliver.private_ip}
    SSH Username: admin
    SSH Password: ${nonsensitive(random_password.lab.result)}
    SSH (internal): ssh admin@${aws_network_interface.sliver.private_ip}
    Operator:     Port 31337 (gRPC multiplexer)
    Guacamole:    Sliver C2 Server (SSH)

  +---------------------------------------------------------------------+
  | 4. HAVOC C2 SERVER                                                  |
  +---------------------------------------------------------------------+
    Private IP:   ${aws_network_interface.havoc.private_ip}
    SSH Username: admin
    SSH Password: ${nonsensitive(random_password.lab.result)}
    SSH (internal): ssh admin@${aws_network_interface.havoc.private_ip}
    Havoc User:   operator
    Havoc Pass:   ${nonsensitive(random_password.lab.result)}
    Guacamole:    Havoc C2 Desktop (VNC) | Havoc C2 Server (SSH)

  +---------------------------------------------------------------------+
  | 5. APACHE REDIRECTOR                                                |
  +---------------------------------------------------------------------+
    Public IP:    ${aws_eip.redirector.public_ip}
    Private IP:   ${aws_network_interface.redirector.private_ip}
    Domain:       ${var.redirector_domain != "" ? var.redirector_domain : "c2.example.com"}
    SSH Username: admin
    SSH Password: ${nonsensitive(random_password.lab.result)}
    SSH (external): ssh -i ${var.ssh_key_name}.pem admin@${aws_eip.redirector.public_ip}
    SSH (internal): ssh admin@${aws_network_interface.redirector.private_ip}
    C2 Header:    ${var.c2_header_name}: ${local.c2_header_value}
    URI Routing:  ${var.mythic_uri_prefix}/ -> Mythic
                  ${var.sliver_uri_prefix}/ -> Sliver
                  ${var.havoc_uri_prefix}/ -> Havoc
    Decoy Page:   CloudEdge CDN maintenance (no header = decoy)
${var.enable_external_vpn ? <<-VPNINFO

  +---------------------------------------------------------------------+
  | 5b. EXTERNAL VPN ROUTING (OpenVPN + WireGuard)                      |
  +---------------------------------------------------------------------+
    Status:       ENABLED
    WG Server:    ${aws_network_interface.redirector.private_ip} (redirector, wg0: 10.100.0.1)
    WG Client:    ${aws_network_interface.guacamole.private_ip}  (guacamole, wg0: 10.100.0.2)
    Target CIDRs: ${join(", ", var.external_vpn_cidrs)}
    VPN Service:  sudo systemctl {start|stop|status} ext-vpn    (on redirector)
    WG Status:    sudo wg show                                   (on redirector or guacamole)

    NOTE: WireGuard is configured automatically at boot -- no pre-deploy key setup needed.

    Traffic path (internal -> CTF target):
      [Teamserver/WIN-OPERATOR]
        -> default VPC route -> guacamole (wg0 gateway, MASQUERADE)
        -> WireGuard tunnel (UDP 51820) -> redirector (wg0 server)
        -> tun0 (OpenVPN, MASQUERADE) -> CTF target

    Quick Start:
      1. Transfer .ovpn to WIN-OPERATOR via Guacamole:
         Guacamole sidebar (Ctrl+Alt+Shift) -> Devices -> upload .ovpn
      2. SCP to redirector from WIN-OPERATOR:
         scp lab.ovpn admin@${aws_network_interface.redirector.private_ip}:~/vpn/
      3. Start VPN service on redirector:
         sudo systemctl start ext-vpn
      4. Verify WireGuard tunnel is up:
         sudo wg show          (redirector: should list guacamole as peer with handshake time)
         sudo wg show          (guacamole: should list redirector as peer with handshake time)
      5. Verify routing from any internal machine:
         ping <ctf-target-ip>
VPNINFO
: ""}
  +---------------------------------------------------------------------+
  | 6. WINDOWS OPERATOR WORKSTATION                                     |
  +---------------------------------------------------------------------+
    Private IP:   ${aws_network_interface.windows.private_ip}
    Username:     Administrator
    Password:     ${try(rsadecrypt(aws_instance.windows.password_data, file(var.ssh_private_key_path)), "(not yet available)")}
    Access:       RDP via Guacamole
    Guacamole:    Windows Operator Workstation (RDP)

  EOT

  network_architecture_content = <<-EOT

  +---------------------------------------------------------------------+
  |                     NETWORK ARCHITECTURE                            |
  +---------------------------------------------------------------------+

  VPC A: Team Server Infrastructure (${var.use_default_vpc ? "Default VPC" : var.vpc_cidr})
  +-------------------------+-------------------------------------------+
  |  Mythic C2 Server       |  ${aws_network_interface.mythic.private_ip}
  |  Sliver C2 Server       |  ${aws_network_interface.sliver.private_ip}
  |  Havoc C2 Server        |  ${aws_network_interface.havoc.private_ip}
  |  Guacamole              |  ${aws_network_interface.guacamole.private_ip} (priv)  /  ${aws_eip.guacamole.public_ip} (pub)
  |  Windows Operator       |  ${aws_network_interface.windows.private_ip}
  +-------------------------+-------------------------------------------+

  VPC B: Redirector Infrastructure (${aws_vpc.redirector.cidr_block})
  +-------------------------+-------------------------------------------+
  |  Apache Redirector      |  ${aws_network_interface.redirector.private_ip} (priv)  /  ${aws_eip.redirector.public_ip} (pub)
  +-------------------------+-------------------------------------------+

  VPC Peering: VPC A <-> VPC B

  C2 Traffic Flow  (ports 80/443 - header + URI validation):

    [Target]
       |
       v  HTTPS / HTTP
    ${aws_eip.redirector.public_ip}  (Apache Redirector)
       |
       |  Required:  ${var.c2_header_name}: ${local.c2_header_value}
       |
       +--  ${format("%-25s", format("%s/", var.mythic_uri_prefix))}-->  ${format("%-15s", aws_network_interface.mythic.private_ip)}  (Mythic)
       +--  ${format("%-25s", format("%s/", var.sliver_uri_prefix))}-->  ${format("%-15s", aws_network_interface.sliver.private_ip)}  (Sliver)
       +--  ${format("%-25s", format("%s/", var.havoc_uri_prefix))}-->  ${format("%-15s", aws_network_interface.havoc.private_ip)}  (Havoc)
       +--  ${format("%-25s", "[no valid header]")}-->  Decoy page (CloudEdge CDN)

${var.enable_external_vpn ? <<-VPNARCH

  External VPN Routing (HTB / VL / PG via OpenVPN + WireGuard):
  +-------------------------+-------------------------------------------+
  |  WG Server (redirector) |  wg0: 10.100.0.1
  |  WG Client (guacamole)  |  wg0: 10.100.0.2
  |  Routed CIDRs           |  ${join(", ", var.external_vpn_cidrs)}
  +-------------------------+-------------------------------------------+

    [Internal Machine]
       |
       v  VPC route (ExtVPN CIDRs) -> guacamole ENI
    Guacamole  (wg0: 10.100.0.2, MASQUERADE)
       |
       v  WireGuard tunnel (UDP 51820)
    Redirector  (wg0: 10.100.0.1)
       |
       v  tun0 (OpenVPN, MASQUERADE)
    [CTF Target]

VPNARCH
: ""}
  EOT
}

output "deployment_info" {
  description = "Full deployment details for all lab instances"
  value       = local.deployment_info_content
}

output "network_architecture" {
  description = "Network architecture diagram with actual IPs"
  value       = local.network_architecture_content
}

resource "local_file" "deployment_info" {
  filename = "${path.root}/deployment_info.txt"
  content  = "${local.deployment_info_content}\n${local.network_architecture_content}"
}
