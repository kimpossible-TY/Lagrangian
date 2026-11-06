#!/usr/bin/env python3
"""Compatibility entrypoint for the shared Homepage and document Reader."""
import sys
sys.dont_write_bytecode = True
from flow_reader.server.home import main

if __name__ == "__main__":
    main()
