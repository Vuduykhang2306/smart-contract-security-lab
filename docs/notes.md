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

## Invariant suite tìm ra thứ mắt mình bỏ sót

Viết bộ invariant cho bản đã vá, tưởng chỉ là thủ tục xác nhận lại mấy bản vá
đã đúng. Đến tính chất thứ hai thì vỡ ra chuyện khác.

INV-02 phát biểu: *mọi ETH mà contract đã hứa trả đều phải có số dư đỡ đằng sau*
(`sum(feesOwed) + sum(pendingDividend) <= address(this).balance`). Phát biểu
xong thì câu hỏi tiếp theo tự đến: đường nào làm số dư đi mà sổ sách không đi?

`_swapBack()` chi `address(this).balance`. Pool cổ tức nằm đúng trong số dư đó.

Nạp 10 ETH cổ tức cho một người, rồi một người khác bán 1.000 token: ví phí nhận
6 ETH mỗi bên, tổng 12 ETH, trong đó 10 là tiền cổ tức của người kia. Sổ vẫn ghi
người đó được 10 ETH. Không cần kẻ tấn công, không cần thứ tự đặc biệt.

Cay nhất là tôi đã đọc đúng hàm `_swapBack` hai lần rồi, một lần cho M-01 một
lần cho M-02. Cả hai lần câu hỏi trong đầu đều là *"lời gọi này có an toàn
không"*. Không lần nào hỏi *"đây là tiền của ai"*.

Bài học: đọc hàm thì thấy được lỗi trong hàm. Muốn thấy lỗi giữa các hàm thì
phải phát biểu bất biến của cả hệ thống rồi đi tìm đường phá nó. Đó mới là thứ
invariant testing làm được mà unit test không làm được — unit test chỉ chứng minh
được kịch bản mình đã nghĩ ra.

Bản vá tình cờ đã đóng H-04 từ trước, vì bản `Fixed` tính `received` bằng hiệu số
dư trước và sau swap. Nhưng đó là may, không phải do tôi nhìn ra vấn đề.

## Chạy Echidna trên đúng bộ tính chất đó (issue #2)

Ý ban đầu là "hai công cụ khác nhau, cái này sót thì cái kia bắt". Chạy xong thì
cả hai đều xanh, không cái nào tìm thêm được gì. Kết quả âm, ghi vào đúng như
vậy, không tô vẽ thành cái gì khác.

Nhưng lúc ngồi nhìn bốn dòng `passing` thì mới thấy vấn đề thật: **làm sao biết
nó xanh vì code đúng hay xanh vì harness chưa chạm tới?** Output hai trường hợp
giống hệt nhau. Bộ Foundry còn có `callSummary()` in ra số lần gọi từng hành
động, Echidna thì không in gì cả.

Nên tôi làm thêm một harness thứ hai, y hệt harness kia, chỉ đổi đúng một dòng:
deploy `MemeTax` thay vì `MemeTaxFixed`. Cùng tập hành động, cùng khoảng chặn,
cùng bốn tính chất. Nếu bộ tính chất này có giá trị thì nó **phải** đỏ ở đây.

Nó đỏ đúng hai chỗ: INV-03 (trần thuế) và INV-02 (ETH đã hứa phải có số dư đỡ).
INV-02 chính là H-04. Echidna đi tới nó trong 5 lời gọi — nạp cổ tức, rồi một
lệnh mua bán bình thường — mà trong harness không hề có chữ `_swapBack`.

Hai chỗ mất thời gian:

- `crytic-compile` mặc định bỏ qua thư mục `test/` khi build bằng Foundry, nên
  Echidna báo "contract not found". Phải thêm `cryticArgs: ["--foundry-compile-all"]`.
- Echidna nạp `balanceContract` bằng cách gửi ETH kèm giao dịch deploy, nên
  constructor của harness phải `payable`. Không thì deploy revert và thông báo
  lỗi chỉ nói chung chung là "revert, out-of-gas, ...".

Bài học đáng giữ: **một lần fuzz ra xanh chưa phải là bằng chứng.** Bằng chứng
là khi mình chứng minh được cùng bộ tính chất đó biết đỏ. Từ giờ viết invariant
suite nào cũng phải có đối chứng âm đi kèm, và cho CI canh luôn cái đối chứng.

## Việc chưa làm

Phần Solana mới có checklist, chưa có PoC. Viết được lab Anchor cho mấy lỗi
account validation thì mới gọi là hiểu.
