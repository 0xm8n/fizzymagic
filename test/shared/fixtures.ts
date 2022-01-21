import { Wallet, Contract,  } from 'ethers'
import { MockProvider, deployContract } from 'ethereum-waffle'
import FizzyTradeToken from '../../build/FizzyTradeToken.json'

const overrides = {
  gasLimit: 9999999
}

interface V2Fixture {
  fizzyTradeToken: Contract
}

export async function v2Fixture([deployer,execAddr]: Wallet[], provider: MockProvider): Promise<V2Fixture> {
  const fizzyTradeToken = await deployContract(deployer, FizzyTradeToken, ['CAKE Trade Token', 'tCAKE', execAddr.address])

  return {
    fizzyTradeToken
  }
}
