# setup project
## initial project
```
mkdir my-project
cd my-project
node -v
npm init -y
npx hardhat

mkdir contracts scripts test
```

## config project
### edit hardhat.config.js
- add require lib
```
require('@nomiclabs/hardhat-waffle');
require('solidity-coverage');
```
- update solidity version
```
  solidity: "0.8.5",
```
### edit package.json
- update scripts command
```
  "scripts": {
    "build": "hardhat compile",
    "test:light": "hardhat test",
    "test": "hardhat coverage",
    "deploy:local": "hardhat run --network localhost scripts/DeployMyContract.js",
    "local-testnet": "hardhat node"
  },
```

# install dependency to local folder
```
npm install --save-dev hardhat
npm install --save-dev @nomiclabs/hardhat-waffle @nomiclabs/hardhat-ethers ethereum-waffle chai solidity-coverage
```

## OR USE THIS after clone project
```
npm install
```

# build and test

## build
```
npm run build
```

## test
```
npm run test
```

## start localhost testnet
```
npm run local-testnet
```

### deploy to localhost testnet
```
npm run deploy:local
```