# 💰 Referral Bonus Smart Contract

A Clarity smart contract for managing employee referral bonuses on the Stacks blockchain. Pay crypto bonuses automatically when referrals lead to successful hires! 🎯

## 🚀 Features

- 📝 Submit employee referrals with position details
- ✅ Confirm successful hires through hiring managers
- 💸 Automatic bonus payments to referrers
- 📊 Track referral statistics and performance
- 🏦 Contract balance management
- ⚙️ Configurable bonus amounts

## 📋 Contract Functions

### Public Functions

#### `submit-referral`
Submit a new employee referral
```clarity
(submit-referral candidate-principal "Software Engineer")
```

#### `confirm-hire` 
Confirm a successful hire from a referral
```clarity
(confirm-hire referral-id hiring-manager-principal)
```

#### `pay-referral-bonus`
Pay bonus to referrer (owner only)
```clarity
(pay-referral-bonus hire-id)
```

#### `fund-contract`
Add STX to contract balance
```clarity
(fund-contract)
```

#### `withdraw-funds`
Withdraw STX from contract (owner only)
```clarity
(withdraw-funds amount)
```

#### `update-bonus-amount`
Update referral bonus amount (owner only)
```clarity
(update-bonus-amount new-amount)
```

#### `cancel-referral`
Cancel pending referral
```clarity
(cancel-referral referral-id)
```

### Read-Only Functions

#### `get-referral`
Get referral details by ID
```clarity
(get-referral referral-id)
```

#### `get-hire`
Get hire details by ID
```clarity
(get-hire hire-id)
```

#### `get-user-referrals`
Get all referrals submitted by user
```clarity
(get-user-referrals user-principal)
```

#### `get-referrer-stats`
Get referrer performance statistics
```clarity
(get-referrer-stats referrer-principal)
```

#### `get-contract-stats`
Get overall contract statistics
```clarity
(get-contract-stats)
```

## 🔄 Workflow

1. **Submit Referral** 📤
   - Employee submits referral with candidate and position
   - Referral gets unique ID and "pending" status

2. **Confirm Hire** ✅
   - Hiring manager confirms successful hire
   - Creates hire record linked to referral
   - Updates referrer statistics

3. **Pay Bonus** 💰
   - Contract owner pays bonus to referrer
   - Transfers STX from contract to referrer
   - Updates payment status and statistics

## 💾 Data Structures

### Referral
- `referrer`: Principal who made referral
- `candidate`: Principal being referred
- `position`: Job position (string)
- `bonus-amount`: Bonus amount in micro-STX
- `created-at`: Block timestamp
- `status`: "pending", "hired", or "cancelled"

### Hire
- `referral-id`: Associated referral ID
- `hiring-manager`: Principal who confirmed hire
- `candidate`: Hired candidate principal
- `hire-date`: Block timestamp of hire
- `confirmed`: Boolean confirmation status
- `bonus-paid`: Boolean payment status

## 🛠️ Setup & Usage

### Prerequisites
- [Clarinet](https://docs.hiro.so/stacks/clarinet) installed
- Node.js for testing

### Installation
```bash
git clone <repository-url>
cd Referral-Bonus-Smart-Contract
clarinet check
```

### Testing
```bash
npm install
npm test
```

### Deployment
```bash
clarinet deploy
```

## 📊 Contract Configuration

- **Default Bonus Amount**: 1,000,000 micro-STX (1 STX)
- **Owner**: Contract deployer
- **Max Referrals per User**: 100
- **Max Hires per Manager**: 100

## 🔧 Error Codes

- `u100`: Owner only function
- `u101`: Record not found
- `u102`: Record already exists
- `u103`: Insufficient contract balance
- `u104`: Invalid status
- `u105`: Unauthorized access
- `u106`: Invalid amount
- `u107`: Referral not found
- `u108`: Hire already confirmed
- `u109`: Hire not confirmed
- `u110`: Bonus already paid



