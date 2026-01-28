# rust-mlua2

Rust + egui + mlua による Lua GUI プログラミング環境

## 仕様要約

- Rust/egui/egui-winit/egui-wgpu + mlua (Lua 5.4)
- Lua から egui ウィンドウ生成・描画APIを呼び出し可能
- Lua スクリプトは coroutine でフレームごとに resume/yield
- VirtualWindow 非使用、egui::Window 直利用
- ファイル実行/REPL 両対応

## Lua API
- egui.create_window(title)
- w:cls(r,g,b)
- w:scroll(dx,dy,r,g,b)
- w:point(x,y,r,g,b)
- w:line(x1,y1,x2,y2,r,g,b)
- w:circle(x,y,radius,r,g,b)
- w:settextcolor(r,g,b)
- w:gettextcolor()
- w:text(x,y,...)

## TODO

- [x] eguiアプリ雛形実装 (main.rs)
- [x] Lua VM雛形実装 (luamod.rs)
- [x] egui/Lua連携API実装
- [x] Luaファイル実行・REPL
- [x] サンプルLuaスクリプト動作確認
- [ ] エラーハンドリング・最終要件確認

---

## サンプルLuaスクリプト

```
w = egui.create_window("Sample")
while true do
  w:cls(0,0,0)
  w:circle(100,100,50,255,0,0)
  w:text(10,10,"Hello","egui","Lua")
  coroutine.yield()
end
```

---

### メモ
- main.rs: egui/winit/wgpu初期化・引数処理まで完了
- luamod.rs: LuaEngine雛形・egui.create_window・run_file/repl・coroutine・pointまで完了
- サンプルLuaスクリプトのAPI群を順次実装中
