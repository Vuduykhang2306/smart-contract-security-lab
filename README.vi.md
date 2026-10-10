# Smart Contract Security Lab

[![CI](https://github.com/Vuduykhang2306/smart-contract-security-lab/actions/workflows/ci.yml/badge.svg)](https://github.com/Vuduykhang2306/smart-contract-security-lab/actions/workflows/ci.yml)

Một bài audit smart contract làm trọn từ đầu đến cuối. Repo gồm một tax token
có lỗi, PoC chạy được cho từng lỗi, báo cáo, bản đã vá, và bộ retest chạy lại
mọi exploit trên bản vá.

Đây là bài tôi tự đặt ra để luyện. Contract mục tiêu do tôi tự viết cho repo
này, nên không có code của bên thứ ba và cũng không phải sản phẩm giao cho
khách hàng nào. Thứ tôi muốn luyện là cả quy trình: mô hình hoá mối đe doạ ->
đọc code thủ công -> PoC -> báo cáo -> vá -> retest.

Nên đọc báo cáo trước: [`reports/2026-09_MemeTax_audit-report.md`](reports/2026-09_MemeTax_audit-report.md)
(báo cáo viết bằng tiếng Anh, theo format của các công ty audit)

```bash
git clone https://github.com/Vuduykhang2306/smart-contract-security-lab
cd smart-contract-security-lab
forge test -vv
```

```
Ran 10 test suites: 23 tests passed, 0 failed
  13 exploit trên src/MemeTax.sol
   9 retest trên src/fixed/MemeTaxFixed.sol
   1 bộ invariant trên bản đã vá (4 tính chất)
```

## Các finding

`src/MemeTax.sol` là một ERC-20 tax token giống các đợt launch memecoin ngoài
thực tế: thuế mua/bán được swap qua DEX ngay trong `_transfer`, có giới hạn ví,
có blacklist, và một pool cổ tức bằng ETH.

| ID | Mức độ | Nội dung | PoC |
|---|---|---|---|
| H-01 | High | Reentrancy trong `claimDividend()` rút sạch pool cổ tức | [`test/H01_ReentrancyClaimDividend.t.sol`](test/H01_ReentrancyClaimDividend.t.sol) |
| H-02 | High | `setBlacklist()` không kiểm tra quyền gọi, ai cũng đóng băng được ví bất kỳ | [`test/H02_BlacklistAccessControl.t.sol`](test/H02_BlacklistAccessControl.t.sol) |
| H-03 | High | `setTaxes()` không có trần, token có thể thành honeypot sau khi launch | [`test/H03_UnboundedTax.t.sol`](test/H03_UnboundedTax.t.sol) |
| H-04 | High | `_swapBack()` trả toàn bộ số dư ETH, lấy luôn cả pool cổ tức | [`test/H04_SwapBackSweepsDividendPool.t.sol`](test/H04_SwapBackSweepsDividendPool.t.sol) |
| M-01 | Medium | `_swapBack()` không có khoá reentrancy, đang dựa vào một bất biến không được ghi ở đâu | [`test/M01_SwapBackNoLock.t.sol`](test/M01_SwapBackNoLock.t.sol) |
| M-02 | Medium | Trả phí bằng ETH nhưng bỏ qua giá trị trả về, trả hỏng cũng không ai biết | [`test/M02_UncheckedEthTransfer.t.sol`](test/M02_UncheckedEthTransfer.t.sol) |
| L-01 | Low | Công thức tính phí chia trước rồi mới nhân | [`test/L01_FeeRounding.t.sol`](test/L01_FeeRounding.t.sol) |
| L-02 | Low | `setMaxWallet(0)` đóng băng mọi giao dịch không được miễn trừ | [`test/L02_MaxWalletZero.t.sol`](test/L02_MaxWalletZero.t.sol) |
| I-01 | Info | Các hàm setter đặc quyền không phát event | không có |

Chạy riêng một finding kèm trace:

```bash
forge test --match-contract H01 -vvv
```

Nếu chỉ đọc hai finding thì nên đọc M-01 và M-02.

M-01 hiện tại chưa phải là lỗi, và đó là chỗ thú vị. Lúc swap phí, router gọi
ngược lại vào `_transfer`. Thứ duy nhất chặn lần swap thứ hai là việc contract
token đang nằm trong mapping miễn phí, mà mapping đó sinh ra cho việc khác.
Tức là contract chạy đúng là do may. Chỉ cần một lệnh admin nhìn rất bình
thường là lớp chặn đó mất, và từ đó mọi lệnh bán đều revert. PoC dựng lại cả
trạng thái trước và sau.

M-02 là chuyện chọn cách vá. Ý đầu tiên của tôi là kiểm tra giá trị trả về rồi
revert. Làm vậy còn tệ hơn: phần trả phí chạy bên trong lệnh bán của người
dùng, nên chỉ cần một ví nhận phí không nhận được ETH là lệnh bán của tất cả
mọi người bị chặn. Tức là đổi một khoản thất thoát không ai thấy lấy một lỗi
DoS cho cả token. Bản vá ghi lại số phí còn nợ rồi để từng ví tự rút.

H-04 là finding tôi thấy tiếc nhất. Lúc đọc code thủ công tôi bỏ sót nó hoàn
toàn. Nó chỉ lộ ra khi tôi viết bộ invariant và phải viết thành tính chất: mọi
ETH mà contract đã hứa trả đều phải có đủ số dư. `_swapBack()` trả
`address(this).balance`, mà pool cổ tức nằm chung trong số dư đó, nên lệnh bán
bình thường đầu tiên sau khi nạp cổ tức sẽ đem tiền của người khác trả cho ví
phí. Tôi đã đọc hàm đó hai lần, cho M-01 và M-02. Cả hai lần tôi chỉ hỏi "lời
gọi này có an toàn không", chưa lần nào hỏi "đây là tiền của ai".

Những chỗ đi sai trong lúc làm, kể cả hai lần làm M-01 không ra gì, tôi ghi
trong [`docs/notes.md`](docs/notes.md).

## Hai công cụ fuzz và một đối chứng âm

Bốn tính chất trong [`test/invariant/`](test/invariant/) chạy bằng Foundry và
chạy lại bằng Echidna ở [`test/echidna/`](test/echidna/). Cả hai đều pass,
không công cụ nào tìm thêm được gì. Kết quả đó tôi để nguyên như vậy.

Cái có ích lại nằm ở chỗ khác. Fuzz ra xanh có thể là do code đúng, cũng có
thể là do harness chưa bao giờ đi tới đoạn code gây lỗi, mà nhìn output thì
hai trường hợp y như nhau. Nên tôi chạy đúng bộ tính chất đó trên
`src/MemeTax.sol`, bản tôi biết chắc là có lỗi, và bắt nó phải fail:

```
echidna_supplyIsConserved:       passing
echidna_maxWalletHasFloor:       passing
echidna_ethObligationsAreBacked: FAILED   <- H-04, trong 5 lời gọi
echidna_taxNeverExceedsCap:      FAILED   <- H-03, trong 1
```

CI sẽ fail nếu một trong hai dòng đó tự dưng pass trở lại. Trong harness không
hề có chữ `_swapBack()`, fuzzer tự tìm tới H-04 chỉ từ một lần nạp cổ tức và
một giao dịch bình thường.

## Rà soát công khai

[`reviews/2026-09_FatTokenV5/`](reviews/2026-09_FatTokenV5/) là bài tôi tự rà
soát (không ai thuê) một template token của launchpad, dùng một token đã chết
trên mainnet làm ví dụ. 8 finding (2 High, 2 Medium, 3 Low, 1 Info), 7 PoC chạy
trên fork mainnet, và một khảo sát on-chain xem còn bao nhiêu bản deploy của
template này vẫn còn owner.

Kết quả chính: template này quyết định mọi quyền nguy hiểm ngay trong
constructor, sau đó không có hàm nào bật lại được. Nên người mua chỉ cần đọc
năm giá trị on-chain là biết mình chịu rủi ro gì, và nó sẽ không đổi về sau.
Mục 6 của bài review là năm lệnh đó.

## Cấu trúc

```
src/
  MemeTax.sol              contract mục tiêu - cố tình có lỗi, không được deploy
  fixed/MemeTaxFixed.sol   bản đã vá, mỗi thay đổi gắn mã finding tương ứng
  base/MinimalERC20.sol    ERC-20 cơ bản, ngoài phạm vi audit
test/
  H0*/M0*/L0*.t.sol        mỗi finding một file
  Retest_Fixed.t.sol       chạy lại mọi exploit trên bản vá
  invariant/               4 tính chất kiểm trên bản đã vá
  echidna/                 cùng 4 tính chất chạy bằng Echidna, kèm đối chứng âm
  attackers/, mocks/       contract tấn công và bản mô phỏng router Uniswap V2
reports/
  2026-09_MemeTax_audit-report.md
  report-template.md
docs/
  audit-process.md         quy trình tôi áp dụng cho mọi contract
  checklist-erc20.md       checklist theo từng hàm cho tax token
  checklist-solana-spl.md  checklist Solana/Anchor - chưa có PoC, xem lộ trình
  notes.md                 sổ tay: chỗ nào đi vào ngõ cụt và vì sao
```

## Phương pháp

Bản đầy đủ ở [`docs/audit-process.md`](docs/audit-process.md). Ngắn gọn thì:

1. Mô hình hoá mối đe doạ. Với token, hai câu hỏi tìm ra phần lớn lỗi: người
   giữ token có bị chặn bán không, và tiền có thể ra khỏi contract theo đường
   nào ngoài dự tính không?
2. Đọc code thủ công theo [`docs/checklist-erc20.md`](docs/checklist-erc20.md),
   làm phần nhanh trước: kiểm soát quyền, rồi CEI, rồi số học, rồi giới hạn
   giá trị.
3. Phân tích tĩnh (`forge lint`) để lấy manh mối, không coi output của nó là
   finding. Nó bắt được M-02 và gợi ý tới M-01, nhưng không bắt được H-02 hay
   H-03 vì cả hai đều là lỗi thiếu code, không có gì để so mẫu. Mục 5 của báo
   cáo ghi cái nào bị loại và vì sao.
4. Có PoC rồi mới viết báo cáo. Finding nào không có test fail thì không đưa
   vào. Khoảng một nửa số chỗ tôi nghi ban đầu bị loại ở bước này.
5. Mức độ = tác động × khả năng xảy ra. Rủi ro tập trung quyền được chấm theo
   thiệt hại của người giữ token không thoát ra được, không chấm theo việc đội
   ngũ trông có đáng tin hay không.
6. Retest, và xem diff để chắc bản vá chỉ có những sửa đổi đã thống nhất.

## Lộ trình

Theo dõi bằng issue, xếp theo thứ tự tôi định làm.

- ~~[#1](../../issues/1) Bộ invariant test bằng Foundry~~ xong, và nó tìm ra H-04
- ~~[#2](../../issues/2) Property test bằng Echidna trên cùng các bất biến đó~~ xong, xem phần đối chứng âm ở trên
- [#3](../../issues/3) Lab Anchor để có PoC thật cho checklist Solana
- [#4](../../issues/4) Writeup Ethernaut và Damn Vulnerable DeFi

## Giới thiệu

Vũ Duy Khang, sinh viên năm nhất ngành An toàn thông tin (định hướng
Blockchain) tại PTIT TP. Hồ Chí Minh. Đang tìm vị trí thực tập Smart Contract
Auditor.

- GitHub [@Vuduykhang2306](https://github.com/Vuduykhang2306)
- Email vuduykhang23062008@gmail.com

## Giấy phép

MIT. Các contract trong `src/` cố tình có lỗ hổng, chỉ dùng để học. Đừng
deploy.
