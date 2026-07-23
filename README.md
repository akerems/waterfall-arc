# Waterfall

Waterfall, Arc Testnet üzerinde çalışan basit bir USDC treasury sözleşmesidir.

Treasury'ye gönderilen USDC, önceden belirlenen kurallara göre sırayla dağıtılır.
Önceki kurallar önceliklidir. Bakiye yetersizse sonraki kurallar daha az ödeme
alır veya hiç ödeme alamaz.

## Şu anki durum

Sözleşme tarafının ilk sürümü hazır.

- Yüzdelik ödeme
- Sabit ödeme
- Hedef bakiyeye tamamlama
- Kalan bakiyenin tamamını gönderme
- En fazla 6 sıralı kural
- Owner tarafından kural yönetimi
- Herkes tarafından çalıştırılabilen dağıtım
- Pause, unpause ve acil çekim
- Dağıtım önizlemesi

Frontend ve Arc Testnet deployment henüz eklenmedi.

## Örnek dağıtım

100 USDC için:

| Kural | Tutar |
| --- | ---: |
| Taxes | 20 USDC |
| Supplier | 30 USDC |
| Reserve | 25 USDC |
| Profit | 25 USDC |

Reserve adresinde zaten 25 USDC varsa ikinci dağıtımda reserve ödeme almaz ve
profit 50 USDC alır.

## Testler

Testlerde kural kontrolleri, yetkiler, pause işlemleri, yetersiz bakiye,
dağıtım önizlemesi ve temel demo senaryoları kontrol ediliyor.

Son durum:

```text
26 tests passed
0 tests failed
```

## Kurulum

Foundry kurulu olmalıdır.

```bash
cd contracts
forge install OpenZeppelin/openzeppelin-contracts@v5.4.0 --no-commit
forge install foundry-rs/forge-std@v1.9.7 --no-commit
forge build
forge test
```

## Proje yapısı

```text
contracts/
├── src/WaterfallTreasury.sol
├── test/WaterfallTreasury.t.sol
├── test/mocks/MockUSDC.sol
├── foundry.toml
└── remappings.txt
```

`MockUSDC` yalnızca yerel testlerde kullanılır. Arc Testnet üzerinde resmi USDC
kontratı kullanılacaktır.

Hackathon prototipidir. Denetlenmemiştir. Yalnızca testnet kullanımı içindir.
