ANVIL_PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

build:; forge build

NETWORK_ARGS := --rpc-url http://127.0.0.1:8545 --private-key $(ANVIL_PRIVATE_KEY) --broadcast

deploy:
	@forge script script/DeployDSC.s.sol:DeployDSC $(NETWORK_ARGS)