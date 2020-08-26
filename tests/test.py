#!/usr/bin/env python3

import os
import requests
import sys
import types
import importlib.machinery


TFVARS_FILE = '../terraform/prod.tfvars'


class Request():

    def __init__(self, method):
        self.headers = {}
        self.headers['Authorization'] = data.api_key
        self.method = method

    def get_json(self):
        ip = requests.get('https://checkip.amazonaws.com').text.strip()
        return {"CURRENT_IP": ip}


loader = importlib.machinery.SourceFileLoader('data', TFVARS_FILE)
data = types.ModuleType(loader.name)
loader.exec_module(data)
os.environ['GCP_PROJECT'] = data.project
os.environ['REGION'] = data.region
os.environ['ZONE'] = data.zone
os.environ['USER'] = data.user
os.environ['API_KEY_SHA256'] = data.api_key_sha256
os.environ['SSH_PUBLIC_KEY'] = data.ssh_public_key

import main 
request = Request(sys.argv[1])
main.handler(request)
