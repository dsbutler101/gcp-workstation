"""
Cloud Function to create/start and terminate workstation VM instance
"""

import googleapiclient.discovery
import sys
import os
import json
import hashlib
import time
from flask import abort

PROJECT_ID      = os.environ.get('GCP_PROJECT')
REGION          = os.environ.get('REGION')
ZONE            = os.environ.get('ZONE')
USER            = os.environ.get('USER')
SSH_PUBLIC_KEY  = os.environ.get('SSH_PUBLIC_KEY')
MACHINE_TYPE    = "e2-small"
INSTANCE        = "centos8"
DNS_NAME        = INSTANCE + "." + PROJECT_ID.replace("-", ".") + "."
FIREWALL_NAME   = "ssh-from-roaming-to-workstation"
SUBNETWORK      = "main-" + REGION
INSTANCE_CONFIG = {
  "kind": "compute#instance",
  "name": INSTANCE,
  "zone": "projects/" + PROJECT_ID + "/zones/" + ZONE,
  "machineType": "projects/" + PROJECT_ID + "/zones/" + ZONE + "/machineTypes/" + MACHINE_TYPE,
  "displayDevice": {
    "enableDisplay": False
  },
  "metadata": {
    "kind": "compute#metadata",
    "items": [
        {
            "key": "ssh-keys",
            "value": USER + ":" + SSH_PUBLIC_KEY
        },
        {
            "key": "startup-script",
            "value": "#!/bin/bash\n\nsleep 20\nif [ -d \"/etc/ssh/ssh_host\" ]\nthen\ncp /etc/ssh/ssh_host/ssh_host_* /etc/ssh/\nelse\nmkdir /etc/ssh/ssh_host\ncp /etc/ssh/ssh_host_* /etc/ssh/ssh_host/\nfi"
        }
    ]
  },
  "tags": {
    "items": ["workstation"]
  },
  "disks": [
    {
      "kind": "compute#attachedDisk",
      "type": "PERSISTENT",
      "boot": True,
      "mode": "READ_WRITE",
      "autoDelete": False,
      "deviceName": INSTANCE,
      "source": "projects/" + PROJECT_ID + "/zones/" + ZONE + "/disks/workstation-" + INSTANCE
    }
  ],
  "canIpForward": False,
  "networkInterfaces": [
    {
      "kind": "compute#networkInterface",
      "subnetwork": "projects/" + PROJECT_ID + "/regions/" + REGION + "/subnetworks/" + SUBNETWORK,
      "accessConfigs": [
        {
          "kind": "compute#accessConfig",
          "name": "External NAT",
          "type": "ONE_TO_ONE_NAT",
          "networkTier": "STANDARD"
        }
      ],
      "aliasIpRanges": []
    }
  ],
  "serviceAccounts": [
    {
      "email": "workstation-instance@" + PROJECT_ID + ".iam.gserviceaccount.com",
      "scopes": [
        "https://www.googleapis.com/auth/cloud-platform"
      ]
    }
  ],
  "description": "",
  "labels": {},
  "scheduling": {
    "preemptible": True,
    "onHostMaintenance": "TERMINATE",
    "automaticRestart": False,
    "nodeAffinities": []
  },
  "deletionProtection": False,
  "reservationAffinity": {
    "consumeReservationType": "ANY_RESERVATION"
  },
  "shieldedInstanceConfig": {
    "enableSecureBoot": False,
    "enableVtpm": True,
    "enableIntegrityMonitoring": True
  }
}

compute = googleapiclient.discovery.build('compute', 'v1', cache_discovery = False)
dns     = googleapiclient.discovery.build('dns', 'v1', cache_discovery = False)
service = googleapiclient.discovery.build('cloudresourcemanager', 'v1', cache_discovery = False)

def workstation_manager(request):
  try:
    if "Authorization" in request.headers:
      api_key = request.headers['Authorization']
      hash_string = hashlib.sha256(api_key.encode()).hexdigest()
    else:
      hash_string = None
    if hash_string == os.environ.get("API_KEY_SHA256"):
      if request.method == "POST":
        current_ip = request.get_json()['CURRENT_IP']
        print("Creating preemtible instance from persistent disk")
        try:
          operation = compute.instances().insert(
            project = PROJECT_ID,
            zone    = ZONE,
            body    = INSTANCE_CONFIG
          ).execute()
        except:
          print("Error cannot create instance, attempting to start existing instance instead")
          operation = compute.instances().start(
            project  = PROJECT_ID,
            zone     = ZONE,
            instance = INSTANCE
          ).execute()
        #print(operation)
        print("Updating firewall to allow access from source IP: " + current_ip)
        compute.firewalls().patch(
          firewall = FIREWALL_NAME,
          body     = {"name": FIREWALL_NAME, "sourceRanges": [ current_ip + "/32"]},
          project  = PROJECT_ID
        ).execute()
        print("Waiting for instance to start")
        compute.zoneOperations().wait(
            project = PROJECT_ID,
            operation = operation['name'],
            zone = ZONE
        ).execute()
        print("Getting external IP address of instance")
        r = compute.instances().get(
          project  = PROJECT_ID,
          zone     = ZONE,
          instance = INSTANCE
        ).execute()
        instance_external_ip = r['networkInterfaces'][0]['accessConfigs'][0]['natIP']
        print("Updating DNS to point new target instance IP: " + instance_external_ip)
        r = dns.resourceRecordSets().list(
          managedZone = PROJECT_ID,
          project     = PROJECT_ID,
          name        = DNS_NAME
        ).execute()
        dns_change = {
          "deletions": r['rrsets'],
          "additions": [{
            "name": DNS_NAME,
            "type": "A",
            "ttl": 30,
            "rrdatas": [instance_external_ip]
          }]
        }
        dns.changes().create(
          project = PROJECT_ID,
          managedZone = PROJECT_ID,
          body = dns_change
        ).execute()
        return instance_external_ip
      elif request.method == "DELETE":
        print("Terminating instance")
        compute.instances().delete(
          project  = PROJECT_ID,
          zone     = ZONE,
          instance = INSTANCE
        ).execute()
        return "Instance deleted"
      else:
        print("Invalid method, aborting")
        return abort(403)
    else:
      print("Unauthenticated request, sleeping for 10 secs")
      time.sleep(10)
      return abort(401)
  except Exception as e:
    print(repr(e))
    time.sleep(5)
