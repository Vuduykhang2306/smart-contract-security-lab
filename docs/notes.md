# Ghi chú khi làm bài này

Sổ tay cá nhân, viết tiếng Việt. Phần nào đi vào ngõ cụt thì ghi lại luôn, vì
lần sau gặp lại còn nhớ tại sao.

## M-01 phải làm lại ba lần

Ý định ban đầu: cho `_swapBack()` bị tái nhập qua router rồi tự gọi lại chính
nó, đệ quy tới cạn stack, mọi lệnh bán revert. Viết xong PoC thì test... pass
một cách vô lý: lệnh bán chạy bình thường.

Lý do: router kéo token bằng `transferFrom(token, pair, amount)`, nên khung gọi
lại có `from == address(token)`. Mà constructor đã đặt
`isExcludedFromFee[address(this)] = true`. Điều kiện kích hoạt swap có vế
`!isExcludedFromFee[from]`, vế này thành `false`, nên không có lần swap thứ hai.

Nghĩa là contract **không** có lỗi đệ quy — nhưng thứ chặn nó lại không phải một
khoá tái nhập. Nó là một mapping có mục đích hoàn toàn khác. Không dòng comment
nào nói ra chuyện đó, không assert nào giữ nó.

Chính chỗ đó mới là finding. Đổi hướng viết lại: PoC dựng hai trạng thái, một
lệnh bán chạy bình thường, rồi gọi `setExcludedFromFee(address(token), false)` —
một lệnh admin trông vô hại — và lệnh bán kế tiếp revert.

Bài học: một contract "không có bug" và một contract "có bug nhưng đang bị một
thứ khác che" trông giống hệt nhau trong test. Phải hỏi *cái gì đang giữ bất
biến này*, không chỉ hỏi *bất biến này có đang đúng không*.

Đây cũng là lý do mọi tax token trên mainnet đều có modifier `lockTheSwap`.
Trước khi tự vấp vào, tôi tưởng nó chỉ là thói quen copy-paste.

## M-02: chọn cách vá sai còn tệ hơn để nguyên

Phản xạ đầu tiên khi thấy `call{value:}` bỏ qua return value là thêm
`require(ok)`. Viết xong mới nhận ra: `_swapBack()` chạy bên trong `_transfer`
của người dùng. Nếu ví nhận phí không nhận được ETH và ta revert, thì **mọi lệnh
bán của mọi người đều revert**. Đổi một khoản thất thoát kế toán âm thầm lấy một
vụ DoS toàn hệ thống.

Đúng cách là cộng dồn rồi cho rút (`feesOwed` + `withdrawFees`). Không ai chặn
được ai.

Ghi lại vì nó cho thấy phần khó của audit không nằm ở chỗ tìm ra dòng code sai,
mà ở chỗ trả lời "sửa thế nào thì không đẻ ra lỗi mới".

## L-01 suýt bị thổi phồng

`amount / 100 * taxRate` chia trước khi nhân, giao dịch dưới 100 wei không mất
phí. Lúc đầu định xếp Medium vì nghe có vẻ là "bypass phí".

Tính lại: muốn né 5% phí của 1 token (1e18 wei) thì phải chia thành 1e16 giao
dịch. Gas tốn gấp hàng tỷ lần số phí tiết kiệm được. Không có tấn công kinh tế
nào ở đây.

Hạ xuống Low và ghi rõ lý do trong báo cáo. Một High thổi phồng làm những cái
High thật mất giá.

## Vặt vãnh nhưng mất thời gian

- `forge init` sinh sẵn `.gitignore` có dòng `docs/`. Thêm checklist vào
  `docs/` rồi commit, `git status` sạch bong, tưởng xong. Hơn chục phút sau mới
  phát hiện chưa file nào được theo dõi.
- Báo cáo trích số dòng cụ thể của `MemeTax.sol`. Ước lượng bằng mắt thì sai
  gần hết. Phải `grep -n` lại từng cái. Chạy `forge fmt` xong lại phải kiểm tra
  lần nữa.
- Mock router phải kéo token về **pair**, không phải về router. Lúc đầu viết sai
  thành `transferFrom(msg.sender, address(this), amountIn)` và cả nhánh tái nhập
  biến mất, vì `to != pair` nên điều kiện swap không bao giờ đúng. Đọc lại
  `UniswapV2Router02.swapExactTokensForETHSupportingFeeOnTransferTokens` mới
  thấy nó gửi thẳng cho pair.

## Việc chưa làm

Chưa có invariant test. Hai bất biến rõ ràng nên kiểm:
`sum(balances) == totalSupply` và `sum(feesOwed) <= address(this).balance`.
Unit test chỉ chứng minh được kịch bản mình nghĩ ra; fuzzing mới tìm được kịch
bản mình không nghĩ ra.

Phần Solana mới có checklist, chưa có PoC. Viết được lab Anchor cho mấy lỗi
account validation thì mới gọi là hiểu.
