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
  solidity: "0.8.27",
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
    cat > contracts/GMonad.sol << 'EOL'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

contract GMonad {
    function sayGmonad() public pure returns (string memory) {
        return "gmonad";
    }
}
EOL

    # Buat direktori ignition dan modul deployment
    mkdir -p ignition/modules
    cat > ignition/modules/GMonad.ts << 'EOL'
import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

const GMonadModule = buildModule("GMonadModule", (m) => {
    const gmonad = m.contract("GMonad");
    return { gmonad };
});

export default GMonadModule;
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
        if npx hardhat ignition deploy ./ignition/modules/GMonad.ts --network monadTestnet | tee "$output_file"; then
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
    solidity: "0.8.27",
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
pragma solidity ^0.8.27;

contract GMonad {
    function sayGmonad() public pure returns (string memory) {
        return "gmonad";
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
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

    # Hapus variabel Hardhat
    if [ -f "/root/.config/hardhat-nodejs/vars.json" ]; then
        echo "Menghapus variabel Hardhat..."
        rm -rf /root/.config/hardhat-nodejs
    fi

    # Hapus direktori proyek monad
    if [ -d "monad" ]; then
        echo "Menghapus direktori monad..."
        rm -rf monad
    fi

    if [ -d "monad_verify" ]; then
        echo "Menghapus direktori monad_verify..."
        rm -rf monad_verify
    fi

    # Hapus Node.js versi yang diinstal
    echo "Menghapus Node.js versi 20.11.1..."
    if command -v nvm &> /dev/null; then
        nvm deactivate
        nvm uninstall 20.11.1
    fi

    # Hapus NVM
    echo "Menghapus NVM..."
    rm -rf "$HOME/.nvm"

    # Hapus referensi NVM dari bashrc
    echo "Membersihkan konfigurasi NVM dari bashrc..."
    sed -i '/NVM_DIR/d' ~/.bashrc
    sed -i '/nvm.sh/d' ~/.bashrc
    sed -i '/nvm_find_nvmrc/d' ~/.bashrc

    # Hapus cache npm
    echo "Membersihkan cache npm..."
    if command -v npm &> /dev/null; then
        npm cache clean --force
    fi

    # Hapus dependencies global
    echo "Menghapus dependencies global..."
    if command -v npm &> /dev/null; then
        npm uninstall -g hardhat typescript ts-node
    fi

    echo "Uninstall selesai!"
    echo "Silakan restart terminal Anda untuk menerapkan semua perubahan."
}

# Menu utama
clear
show_logo
echo "================================="
echo "    Monad Contract Tools Menu    "
echo "================================="
echo "1. Deploy Smart Contract"
echo "2. Verify Contract"
echo "3. Uninstall Monad"
echo "4. Exit"
echo "================================="
echo "Choose option (1-4):"
read -r choice

case $choice in
    1)
        deploy_sc
        ;;
    2)
        verify_contract
        ;;
    3)
        uninstall_monad
        ;;
    4)
        echo "Exiting program..."
        exit 0
        ;;
    *)
        echo "Invalid choice!"
        ;;
esac
