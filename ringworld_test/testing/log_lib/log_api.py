# Constants
NUM_STORAGE_SERVERS = 4
NUM_STORAGE_FAILURES = 3
NUM_SWITCHES = 4

def get_storage_server_ids(log_idx):
	# Get storage server ids corresponding to log index

def append(log_entry):
	# Here we append to the end of the log
	# Part 1: Get sequence number
	# Part 2: Store entry durably in storage servers

def readAt(idx):
	# Read at an index
	# Step 1: Find where index is located
	# Step 2: Send broadcast to those servers where it is located
	# Step 3: Wait for reply to those servers

def subscribe(idx):
	# Subscribe at an index
	# Should be an asynchronous function which adds updates to the log to the server's local log
