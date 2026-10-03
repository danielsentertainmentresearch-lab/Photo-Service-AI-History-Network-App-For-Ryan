/// Web3 identities: signing in with a crypto wallet or a decentralised
/// social account instead of an email or phone number.
///
/// Sign-in works by the wallet signing a short "Sign-In with Ethereum"
/// message (EIP-4361; Solana wallets use the same format). The accounts
/// backend checks the signature; no payment or blockchain transaction is
/// involved. Supabase Auth, the recommended backend, verifies Ethereum and
/// Solana sign-ins natively. Wallets connect through WalletConnect (Reown
/// AppKit), which needs a free project id (see docs/LAUNCH_CHECKLIST.md).
library;

enum Web3Chain { ethereum, solana, farcaster }

/// A way to sign in with a Web3 identity, as listed on the account screen.
class Web3Identity {
  final Web3Chain chain;
  final String name;

  /// Popular apps that provide this identity.
  final List<String> examples;

  const Web3Identity(this.chain, this.name, this.examples);
}

const web3Identities = <Web3Identity>[
  Web3Identity(Web3Chain.ethereum, 'Ethereum wallet', [
    'MetaMask',
    'Coinbase Wallet',
    'Rainbow',
    'Trust Wallet',
  ]),
  Web3Identity(Web3Chain.solana, 'Solana wallet', [
    'Phantom',
    'Solflare',
    'Backpack',
  ]),
  Web3Identity(Web3Chain.farcaster, 'Farcaster', ['Warpcast']),
];

/// Web3 names shown instead of a long wallet address when the wallet has
/// one.
const web3NameServices = <String>[
  'ENS (names like sam.eth)',
  'Unstoppable Domains (names like sam.crypto)',
  'Solana Name Service (names like sam.sol)',
];

/// The plain-language explanation behind "What is this?".
const web3Explainer = <(String, String)>[
  (
    'What is a Web3 identity?',
    'It\'s a login you own yourself, instead of one a company keeps for '
        'you. It lives in a wallet app on your phone, like MetaMask or '
        'Phantom.',
  ),
  (
    'How does signing in work?',
    'EventLens asks your wallet app to "sign" a short message. Signing '
        'proves the wallet is yours, the same way a signature on paper '
        'proves a letter is from you. There is no password to remember.',
  ),
  (
    'Does it cost anything?',
    'No. Signing in is free. It is not a payment, it does not move any '
        'money or crypto, and EventLens never asks for your recovery '
        'phrase.',
  ),
  (
    'Names instead of codes',
    'A wallet address is a long code like 0x71C7…976F. If you have a name '
        'linked to it, like sam.eth, EventLens shows the name instead.',
  ),
  (
    'Good to know',
    'Your wallet\'s recovery phrase is the only way back in if you lose '
        'your phone. Nobody, including EventLens, can reset it for you. If '
        'that sounds risky, sign in with email or phone instead.',
  ),
];

/// Builds the EIP-4361 "Sign-In with Ethereum" message the wallet signs.
/// Solana wallets sign the same format with "Solana" in the first line.
String signInMessage({
  required String domain,
  required String address,
  required Uri uri,
  required String nonce,
  required DateTime issuedAt,
  Web3Chain chain = Web3Chain.ethereum,
  int chainId = 1,
  String statement = 'Sign in to EventLens. This is free and is not a '
      'transaction.',
  DateTime? expiresAt,
}) {
  if (chain == Web3Chain.farcaster) {
    throw ArgumentError('Farcaster uses its own Sign In With Farcaster flow.');
  }
  if (!RegExp(r'^[A-Za-z0-9]{8,}$').hasMatch(nonce)) {
    throw ArgumentError('The nonce must be at least 8 letters or digits.');
  }
  final network = chain == Web3Chain.solana ? 'Solana' : 'Ethereum';
  final lines = [
    '$domain wants you to sign in with your $network account:',
    address,
    '',
    statement,
    '',
    'URI: $uri',
    'Version: 1',
    if (chain == Web3Chain.ethereum) 'Chain ID: $chainId',
    'Nonce: $nonce',
    'Issued At: ${issuedAt.toUtc().toIso8601String()}',
    if (expiresAt != null)
      'Expiration Time: ${expiresAt.toUtc().toIso8601String()}',
  ];
  return lines.join('\n');
}

/// Short form of a wallet address for display: 0x71C7…976F.
String shortAddress(String address) => address.length <= 12
    ? address
    : '${address.substring(0, 6)}…${address.substring(address.length - 4)}';
