#!/bin/bash

# Fungsi untuk menampilkan logo dari GitHub
show_logo() {
    echo "Downloading and displaying logo..."
    curl -s https://raw.githubusercontent.com/bangpateng/logo/main/logo.sh | bash
}

# Fungsi untuk mendapatkan dan menampilkan alamat kontrak dari output deployment
get_contract_address() {
    local output_file="deployment_output.txt"
    local contract_address
    
    # Mencari baris yang mengandung alamat kontrak
    contract_address=$(grep -o '0x[a-fA-F0-9]\{40\}' "$output_file")
    
    if [ -n "$contract_address" ]; then
        echo "Contract Address: $contract_address"
        echo "Contract Link: https://testnet.monadexplorer.com/address/$contract_address"
        echo "✅ Contract deployed successfully!"
    else
        echo "❌ Couldn't find contract address in deployment output"
    fi
}

# Fungsi untuk deploy smart contract
deploy_sc() {
    # Install NVM dan Node.js
    echo "Installing NVM..."
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash

    # Setup NVM environment
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

    # Verify NVM installation
    if ! command -v nvm &> /dev/null; then
        echo "NVM installation failed. Please restart your terminal and try again."
        return 1
    fi

    echo "Installing Node.js 20.11.1..."
    nvm install 20.11.1
    nvm use 20.11.1

    # Verify Node.js installation
    if ! command -v node &> /dev/null; then
        echo "Node.js installation failed"
        return 1
    fi

    echo "Node.js $(node -v) installed successfully"

    # Buat dan setup proyek Monad
    mkdir -p monad
    cd monad || exit

    # Inisialisasi proyek
    npm init -y

    # Install dependencies
    echo "Installing project dependencies..."
    npm install --save-dev hardhat @nomicfoundation/hardhat-toolbox-viem typescript ts-node @nomicfoundation/hardhat-ignition

    # Buat tsconfig.json
    cat > tsconfig.json << 'EOL'
{
  "compilerOptions": {
    "target": "es2020",
    "module": "commonjs",
    "moduleResolution": "node",
    "esModuleInterop": true,
    "forceConsistentCasingInFileNames": true,
    "strict": true,
    "skipLibCheck": true,
    "resolveJsonModule": true
  }
}
EOL

    # Membuat hardhat.config.ts
    cat > hardhat.config.ts << 'EOL'
import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-viem";
import { vars } from "hardhat/config";

const config: HardhatUserConfig = {
  solidity: "0.8.19",
  networks: {
    monadTestnet: {
      url: "https://testnet-rpc.monad.xyz/",
      accounts: [vars.get("PRIVATE_KEY")],
      chainId: 10143,
      timeout: 180000,
      gas: 2000000,
      gasPrice: 60806040,
      httpHeaders: {
        "Content-Type": "application/json",
      }
    }
  },
  sourcify: {
    enabled: true,
    apiUrl: "https://sourcify-api-monad.blockvision.org",
    browserUrl: "https://testnet.monadexplorer.com"
  },
  etherscan: {
    enabled: false
  }
};

export default config;
EOL

    # Buat direktori contracts dan file smart contract
    mkdir -p contracts
    cat > contracts/Bangpateng.sol << 'EOL'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Bangpateng {
    address public owner;
    uint256 public faucetAmount = 0.01 ether;
    uint256 public cooldownTime = 24 hours;
    
    mapping(address => uint256) public lastClaimTime;
    
    event FaucetClaimed(address indexed recipient, uint256 amount, uint256 timestamp);
    event FaucetReplenished(uint256 amount, uint256 timestamp);
    event AmountChanged(uint256 newAmount);
    event CooldownChanged(uint256 newCooldown);
    
    constructor() {
        owner = msg.sender;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    receive() external payable {
        emit FaucetReplenished(msg.value, block.timestamp);
    }
    
    function claimFaucet() external {
        require(
            block.timestamp >= lastClaimTime[msg.sender] + cooldownTime,
            "Please wait for cooldown period"
        );
        require(
            address(this).balance >= faucetAmount,
            "Insufficient faucet balance"
        );
        
        lastClaimTime[msg.sender] = block.timestamp;
        
        (bool success, ) = payable(msg.sender).call{value: faucetAmount}("");
        require(success, "Failed to send MONAD");
        
        emit FaucetClaimed(msg.sender, faucetAmount, block.timestamp);
    }
    
    function checkRemainingTime(address _user) external view returns (uint256) {
        if (block.timestamp >= lastClaimTime[_user] + cooldownTime) {
            return 0;
        }
        return (lastClaimTime[_user] + cooldownTime) - block.timestamp;
    }
    
    function setFaucetAmount(uint256 _newAmount) external onlyOwner {
        faucetAmount = _newAmount;
        emit AmountChanged(_newAmount);
    }
    
    function setCooldownTime(uint256 _newCooldown) external onlyOwner {
        cooldownTime = _newCooldown;
        emit CooldownChanged(_newCooldown);
    }
    
    function withdrawAll() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");
        
        (bool success, ) = payable(owner).call{value: balance}("");
        require(success, "Failed to withdraw");
    }
    
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
EOL

    # Buat direktori ignition dan modul deployment
    mkdir -p ignition/modules
    cat > ignition/modules/Bangpateng.ts << 'EOL'
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const BangpatengModule = buildModule("BangpatengModule", (m) => {
    const bangpateng = m.contract("Bangpateng");
    return { bangpateng };
});

export default BangpatengModule;
EOL

    # Set private key
    echo "Masukkan PRIVATE_KEY (tanpa 0x):"
    read -r private_key
    npx hardhat vars set PRIVATE_KEY "$private_key"

    # Compile kontrak 
    echo "Kompilasi kontrak..."
    npx hardhat compile

    # Deploy kontrak dengan retry dan capture output
    echo "Memulai deployment kontrak..."
    deploy_with_retry

    echo "Setup dan deployment selesai!"
}

# Fungsi untuk deploy dengan retry
deploy_with_retry() {
    local max_retries=3
    local wait_time=10
    local attempt=1
    local output_file="deployment_output.txt"
    
    while [ $attempt -le $max_retries ]; do
        echo "Percobaan deployment ke-$attempt dari $max_retries..."
        
        # Capture output deployment ke file
        if npx hardhat ignition deploy ./ignition/modules/Bangpateng.ts --network monadTestnet | tee "$output_file"; then
            echo "Deployment berhasil!"
            # Tampilkan alamat dan link kontrak
            get_contract_address
            return 0
        else
            if [ $attempt -lt $max_retries ]; then
                echo "Deployment gagal, menunggu $wait_time detik sebelum mencoba lagi..."
                sleep $wait_time
                wait_time=$((wait_time * 2))
            fi
        fi
        attempt=$((attempt + 1))
    done
    
    echo "Deployment gagal setelah $max_retries percobaan"
    return 1
}

# Fungsi untuk verifikasi kontrak
verify_contract() {
    echo "==================================="
    echo "    Contract Verification Menu      "
    echo "==================================="
    
    # Minta input alamat kontrak
    echo "Enter contract address to verify (include 0x):"
    read -r contract_address
    
    # Validasi format alamat
    if [[ ! $contract_address =~ ^0x[a-fA-F0-9]{40}$ ]]; then
        echo "❌ Invalid contract address format!"
        return 1
    fi
    
    # Buat direktori proyek jika belum ada
    mkdir -p monad_verify
    cd monad_verify || exit
    
    # Inisialisasi proyek
    npm init -y
    
    # Install dependencies
    echo "Installing verification dependencies..."
    npm install --save-dev hardhat @nomicfoundation/hardhat-toolbox-viem typescript ts-node
    
    # Buat tsconfig.json yang benar
    cat > tsconfig.json << 'EOL'
{
  "compilerOptions": {
    "target": "es2020",
    "module": "commonjs",
    "moduleResolution": "node",
    "esModuleInterop": true,
    "forceConsistentCasingInFileNames": true,
    "strict": true,
    "skipLibCheck": true,
    "resolveJsonModule": true
  }
}
EOL
    
    # Buat hardhat.config.ts untuk verifikasi
    cat > hardhat.config.ts << 'EOL'
import type { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox-viem";

const config: HardhatUserConfig = {
    solidity: "0.8.19",
    networks: {
        monadTestnet: {
            url: "https://testnet-rpc.monad.xyz",
            chainId: 10143
        }
    },
    sourcify: {
        enabled: true,
        apiUrl: "https://sourcify-api-monad.blockvision.org",
        browserUrl: "https://testnet.monadexplorer.com"
    },
    etherscan: {
        enabled: false
    }
};

export default config;
EOL
    
    # Buat direktori contracts
    mkdir -p contracts
    
    # Create the contract file with exact same code as deployed
    cat > contracts/Contract.sol << 'EOL'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract Bangpateng {
    address public owner;
    uint256 public faucetAmount = 0.1 ether;
    uint256 public cooldownTime = 24 hours;
    
    mapping(address => uint256) public lastClaimTime;
    
    event FaucetClaimed(address indexed recipient, uint256 amount, uint256 timestamp);
    event FaucetReplenished(uint256 amount, uint256 timestamp);
    event AmountChanged(uint256 newAmount);
    event CooldownChanged(uint256 newCooldown);
    
    constructor() {
        owner = msg.sender;
    }
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    receive() external payable {
        emit FaucetReplenished(msg.value, block.timestamp);
    }
    
    function claimFaucet() external {
        require(
            block.timestamp >= lastClaimTime[msg.sender] + cooldownTime,
            "Please wait for cooldown period"
        );
        require(
            address(this).balance >= faucetAmount,
            "Insufficient faucet balance"
        );
        
        lastClaimTime[msg.sender] = block.timestamp;
        
        (bool success, ) = payable(msg.sender).call{value: faucetAmount}("");
        require(success, "Failed to send MONAD");
        
        emit FaucetClaimed(msg.sender, faucetAmount, block.timestamp);
    }
    
    function checkRemainingTime(address _user) external view returns (uint256) {
        if (block.timestamp >= lastClaimTime[_user] + cooldownTime) {
            return 0;
        }
        return (lastClaimTime[_user] + cooldownTime) - block.timestamp;
    }
    
    function setFaucetAmount(uint256 _newAmount) external onlyOwner {
        faucetAmount = _newAmount;
        emit AmountChanged(_newAmount);
    }
    
    function setCooldownTime(uint256 _newCooldown) external onlyOwner {
        cooldownTime = _newCooldown;
        emit CooldownChanged(_newCooldown);
    }
    
    function withdrawAll() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");
        
        (bool success, ) = payable(owner).call{value: balance}("");
        require(success, "Failed to withdraw");
    }
    
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
EOL

    # Compile contract
    echo "Compiling contract..."
    npx hardhat compile
    
    # Verify contract using monadTestnet network
    echo "Verifying contract..."
    if npx hardhat verify "$contract_address" --network monadTestnet; then
        echo "✅ Contract verification successful!"
        echo "You can view your verified contract at:"
        echo "https://testnet.monadexplorer.com/address/$contract_address"
    else
        echo "❌ Contract verification failed"
        echo "Please make sure your contract code exactly matches the deployed contract"
    fi
    
    cd ..
}

# Fungsi untuk uninstall
uninstall_monad() {
    echo "Memulai proses uninstall Monad..."

    # Setup NVM environment jika belum
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$
