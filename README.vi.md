# Smart Contract Security Lab

[![CI](https://github.com/Vuduykhang2306/smart-contract-security-lab/actions/workflows/ci.yml/badge.svg)](https://github.com/Vuduykhang2306/smart-contract-security-lab/actions/workflows/ci.yml)

Một bài audit hợp đồng thông minh hoàn chỉnh từ đầu đến cuối: một tax token
thực tế có lỗi cài sẵn, proof of concept chạy được cho từng finding, báo cáo
đầy đủ, bản đã vá, và bộ retest chạy lại mọi exploit trên bản vá.

Đây là bài tự luyện. Contract mục tiêu do tôi viết cho repo này — không rà soát
mã của bên thứ ba, không phải sản phẩm bàn giao cho khách hàng. Thứ nó thể hiện
là quy trình: **mô hình hoá mối đe doạ → rà soát thủ công → PoC → báo cáo → vá →
retest.**

**Đọc trước:** [`reports/2026-09_MemeTax_audit-report.md`](reports/2026-09_MemeTax_audit-report.md)
(báo cáo viết bằng tiếng Anh, theo chuẩn trình bày của các hãng audit)

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

`src/MemeTax.sol` là ERC-20 tax token đúng theo dáng các đợt phát hành memecoin
thực tế: thuế mua/bán được gom và swap qua DEX ngay trong `_transfer`, giới hạn
ví, danh sách đen, và một pool cổ tức bằng ETH.

| ID | Mức độ | Nội dung | PoC |
|---|---|---|---|
| H-01 | High | Reentrancy trong `claimDividend()` rút cạn toàn bộ pool cổ tức | [`test/H01_ReentrancyClaimDividend.t.sol`](test/H01_ReentrancyClaimDividend.t.sol) |
| H-02 | High | `setBlacklist()` thiếu kiểm soát truy cập — ai cũng đóng băng được ví bất kỳ | [`test/H02_BlacklistAccessControl.t.sol`](test/H02_BlacklistAccessControl.t.sol) |
| H-03 | High | `setTaxes()` không có trần — có thể biến token thành honeypot sau khi niêm yết | [`test/H03_UnboundedTax.t.sol`](test/H03_UnboundedTax.t.sol) |
| H-04 | High | `_swapBack()` chi trả trọn số dư ETH, quét luôn pool cổ tức | [`test/H04_SwapBackSweepsDividendPool.t.sol`](test/H04_SwapBackSweepsDividendPool.t.sol) |
| M-01 | Medium | `_swapBack()` không có khoá tái nhập, đang dựa vào một bất biến không ai ghi lại | [`test/M01_SwapBackNoLock.t.sol`](test/M01_SwapBackNoLock.t.sol) |
| M-02 | Medium | Trả phí bằng ETH bỏ qua giá trị trả về — phân phối thất bại âm thầm | [`test/M02_UncheckedEthTransfer.t.sol`](test/M02_UncheckedEthTransfer.t.sol) |
| L-01 | Low | Công thức tính phí chia trước khi nhân | [`test/L01_FeeRounding.t.sol`](test/L01_FeeRounding.t.sol) |
| L-02 | Low | `setMaxWallet(0)` đóng băng mọi giao dịch không được miễn trừ | [`test/L02_MaxWalletZero.t.sol`](test/L02_MaxWalletZero.t.sol) |
| I-01 | Info | Các hàm setter đặc quyền không phát event | — |

Chạy riêng một finding kèm trace:

```bash
forge test --match-contract H01 -vvv
```

Hai finding tôi cho là đáng đọc nhất là **M-01** và **M-02**.

M-01 hôm nay chưa phải lỗi. Quá trình swap phí tái nhập `_transfer` thông qua
router, và thứ duy nhất ngăn một lần swap thứ hai là việc contract token tình cờ
nằm trong mapping miễn phí giao dịch. Contract đúng, nhưng đúng một cách tình cờ
— chỉ cần một lệnh admin trông rất bình thường là hàng rào biến mất và mọi lệnh
bán bắt đầu revert. PoC dựng lại cả hai trạng thái.

M-02 là chuyện chọn đúng cách vá chứ không phải cách đầu tiên nghĩ ra. Phản xạ
của tôi là thêm `require` cho giá trị trả về rồi revert. Như vậy còn tệ hơn: hàm
trả phí chạy bên trong lệnh bán của người dùng, nên một ví nhận phí không nhận
được ETH sẽ chặn lệnh bán của tất cả mọi người. Đổi một khoản thất thoát kế toán
âm thầm lấy một vụ DoS toàn hệ thống. Bản vá cộng dồn phí và để ví tự rút.

**H-04 là finding tôi thấy xấu hổ nhất và cũng mừng nhất.** Lần rà soát thủ công
bỏ sót nó hoàn toàn. Nó chỉ lộ ra khi tôi ngồi viết bộ invariant và buộc phải
phát biểu thành một tính chất: mọi ETH mà contract đã hứa trả đều phải có số dư
đỡ đằng sau. `_swapBack()` chi trả `address(this).balance`, mà pool cổ tức nằm
chung số dư đó, nên lệnh bán bình thường đầu tiên sau một lần nạp cổ tức là đem
tiền người khác trả cho ví phí. Tôi đã đọc đúng hàm đó hai lần rồi, cho M-01 và
M-02, và cả hai lần đều hỏi "lời gọi này có an toàn không" chứ không hỏi "đây là
tiền của ai".

Những hướng đi hỏng trong lúc làm, gồm hai lần viết lại M-01, tôi ghi trong
[`docs/notes.md`](docs/notes.md).

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

Chi tiết trong [`docs/audit-process.md`](docs/audit-process.md). Tóm tắt:

1. **Mô hình hoá mối đe doạ.** Với token, hai câu hỏi tìm ra phần lớn lỗi:
   *người giữ token có thể bị chặn bán không?* và *giá trị có thể rời contract
   theo đường nào mà không ai dự tính không?*
2. **Rà soát thủ công** theo [`docs/checklist-erc20.md`](docs/checklist-erc20.md),
   làm việc rẻ trước — kiểm soát truy cập, rồi CEI, rồi số học, rồi biên giá trị.
3. **Phân tích tĩnh** (`forge lint`) để lấy manh mối. Nó bắt được M-02 và chỉ
   hướng tới M-01, nhưng không thể bắt H-02 hay H-03 vì cả hai đều là lỗi
   *thiếu code* — không có gì để so khớp mẫu. Mục 5 của báo cáo ghi rõ cái nào
   bị loại và vì sao.
4. **Có PoC rồi mới viết báo cáo.** Finding không có test fail thì không được
   đưa vào. Khoảng một nửa số nghi ngờ ban đầu của tôi chết ở bước này.
5. **Xếp mức độ theo `tác động × khả năng xảy ra`**, trong đó rủi ro tập trung
   hoá được chấm theo thiệt hại của người giữ token không thoát được, không phải
   theo mức độ đáng tin của đội ngũ.
6. **Retest**, và soát diff để chắc bản vá không chứa gì ngoài các sửa đổi đã thống nhất.

## Lộ trình

Theo dõi bằng issue, xếp theo thứ tự định làm.

- ~~[#1](../../issues/1) Bộ invariant test bằng Foundry~~ — xong, và nó tìm ra H-04
- [#2](../../issues/2) Property test bằng Echidna trên cùng các bất biến đó
- [#3](../../issues/3) Lab Anchor để có PoC thật đứng sau checklist Solana
- [#4](../../issues/4) Writeup Ethernaut và Damn Vulnerable DeFi

## Giới thiệu

Vũ Duy Khang — sinh viên năm nhất ngành An toàn thông tin, định hướng Blockchain
tại PTIT, TP. Hồ Chí Minh. Đang tìm vị trí thực tập Smart Contract Auditor.

- GitHub [@Vuduykhang2306](https://github.com/Vuduykhang2306)
- Email vuduykhang23062008@gmail.com

## Giấy phép

MIT. Các contract trong `src/` cố tình chứa lỗ hổng và chỉ dùng để nghiên cứu.
Không deploy.
