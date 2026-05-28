# Coolify ACME JSON Certs Map

A lightweight Go utility designed to automatically extract SSL/TLS certificates from Coolify's Traefik `acme.json` file and map them into standard, individual domain directories containing raw PEM files.

## How It Works

The utility uses OS-level notifications to constantly watch for file changes in the Coolify proxy directory. Whenever `acme.json` is updated, it automatically extracts and decodes the SSL certificates, saving them directly to `/data/coolify/proxy/acme/[domain]/` as individual `cert.pem` and `key.pem` files.

## Quick Deployment

You can build and deploy this utility directly on your target server using Docker.

When launching the container, you **must bind the host directory** `/data/coolify/proxy` to the container as a shared volume. This allows the application to directly watch the file system changes and output the extracted certificates back to your host infrastructure in real time.

## Use Case: AdGuard Home (DoT/DoH)

When running AdGuard Home via Coolify, it cannot bind ports 80 or 443 to request its own Let's Encrypt certificates because Coolify's global Traefik instance already occupies them.

Instead of fighting for ports, let Coolify/Traefik handle the certificate generation natively. This utility instantly extracts those certificates to the host file system. You can then simply mount the generated directory into your AdGuard Home container to supply the required keys for **Certificates** setting.
