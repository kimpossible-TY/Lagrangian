#!/usr/bin/env python3
"""Run the document-independent Lagrangian Homepage (no build or service start)."""
import sys
sys.dont_write_bytecode = True
from flow_reader.server.home import main

if __name__ == "__main__":
    main()
