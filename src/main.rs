mod luamod;
mod luaimage;
mod luamidi;
mod luagraphic;
use clap::Parser;
use std::sync::{Arc, Mutex};
use std::collections::HashMap;
use egui::{ColorImage, TextureHandle, TextureOptions};
use egui_winit::winit::window::WindowBuilder;
use egui_winit::winit::event_loop::{EventLoop, ControlFlow};
use egui_winit::winit::event::{Event, WindowEvent};
use luamod::{LuaEngine, register_egui, LuaWindow, load_lua_coroutine};
use mlua::{Thread, ThreadStatus};

#[derive(Parser, Debug)]
#[command(author, version, about)]
struct Args {
    /// Luaファイル（省略時REPL）
    lua_file: Option<String>,
    
    /// 残りのコマンドライン引数
    #[arg(trailing_var_arg = true)]
    rest_args: Vec<String>,
}

fn main() {
    let args = Args::parse();
    let lua_engine_box = Box::new(LuaEngine::new().expect("Lua初期化失敗"));
    let lua_engine: &'static LuaEngine = Box::leak(lua_engine_box);
    {
        // Luaファイルパスとそれ以降のargsを設定
        let mut lua_args = vec![];
        if let Some(ref file) = args.lua_file {
            lua_args.push(file.clone());
        }
        lua_args.extend(args.rest_args.clone());
        let arg_table = lua_engine.lua.create_table().expect("argテーブル作成失敗");
        lua_args.iter().enumerate().for_each(|(i, v)| {
            arg_table.set(i, v.clone()).expect("arg設定失敗");
        });
        lua_engine.lua.globals().set("arg", arg_table).expect("arg設定失敗");
    }
    luamod::register_sleep(&lua_engine.lua).expect("sleep関数登録失敗");
    luamod::register_hpc(&lua_engine.lua).expect("hpc API登録失敗");
    luamod::register_utcdatetime(&lua_engine.lua).expect("utc datetime API登録失敗");
    luamod::register_localdatetime(&lua_engine.lua).expect("local datetime API登録失敗");
    luaimage::register_lua_image(&lua_engine.lua).expect("image API登録失敗");
    luamidi::register(&lua_engine.lua).expect("midi API登録失敗");
    luagraphic::register_lua_graphic(&lua_engine.lua).expect("graphic API登録失敗");
    
    if args.lua_file.is_none() {
        lua_engine.repl().expect("REPL失敗");
        return;
    }
    use egui_winit::State;
    use egui_wgpu::renderer::ScreenDescriptor;
    
    let event_loop = EventLoop::new();
    let window = WindowBuilder::new().with_title("rust-mlua2").with_maximized(true).build(&event_loop).unwrap();
    let mut state = State::new(&event_loop);
    let instance = egui_wgpu::wgpu::Instance::new(egui_wgpu::wgpu::InstanceDescriptor {
        backends: egui_wgpu::wgpu::Backends::all(),
        dx12_shader_compiler: Default::default(),
    });
    let surface = unsafe { instance.create_surface(&window) }.unwrap();
    let adapter = pollster::block_on(instance.request_adapter(&egui_wgpu::wgpu::RequestAdapterOptions {
        power_preference: egui_wgpu::wgpu::PowerPreference::HighPerformance,
        compatible_surface: Some(&surface),
        force_fallback_adapter: false,
    })).expect("No suitable GPU adapters found on the system!");
    let (device, queue) = pollster::block_on(adapter.request_device(&egui_wgpu::wgpu::DeviceDescriptor {
        features: egui_wgpu::wgpu::Features::empty(),
        limits: egui_wgpu::wgpu::Limits::default(),
        label: None,
    }, None)).expect("Failed to create device");
    let size = window.inner_size();
    let surface_format = surface.get_capabilities(&adapter).formats[0];
    let mut config = egui_wgpu::wgpu::SurfaceConfiguration {
        usage: egui_wgpu::wgpu::TextureUsages::RENDER_ATTACHMENT,
        format: surface_format,
        width: size.width,
        height: size.height,
        present_mode: egui_wgpu::wgpu::PresentMode::Fifo,
        alpha_mode: egui_wgpu::wgpu::CompositeAlphaMode::Auto,
        view_formats: vec![],
    };
    surface.configure(&device, &config);
    let mut renderer = egui_wgpu::renderer::Renderer::new(&device, surface_format, None, 1);
    let egui_ctx = egui::Context::default();
    let windows: Arc<Mutex<Vec<Arc<Mutex<LuaWindow>>>>> = Arc::new(Mutex::new(Vec::new()));
    let textures: Arc<Mutex<HashMap<String, TextureHandle>>> = Arc::new(Mutex::new(HashMap::new()));
    let lua_file = args.lua_file.clone();
    static mut LUA_THREAD: Option<Thread<'static>> = None;
    register_egui(&lua_engine.lua, windows.clone()).expect("egui Lua API登録失敗");
    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Poll;
        if let Event::WindowEvent { event: WindowEvent::KeyboardInput { input , .. }, .. } = &event {
            lua_engine.lua.globals().get("egui").and_then(|egui_table: mlua::Table| {
                let handler = egui_table.get::<_, mlua::Function>(
                    "keyhandler"
                );
                match handler {
                    Ok(f) => {
                        f.call::<(mlua::Value, mlua::Value, mlua::Value), ()>(
                            (
                                mlua::Value::String(lua_engine.lua.create_string(&format!("{:?}", input.state)).unwrap()),
                                match input.virtual_keycode {
                                    Some(key) => mlua::Value::String(lua_engine.lua.create_string(&format!("{:?}", key)).unwrap()),
                                    None => mlua::Value::Nil,
                                },
                                mlua::Value::Integer(input.scancode as i64)
                            )
                        ).ok();
                    },
                    Err(_) => { /* no handler registered */ }
                };
                Ok(())
            }).ok();
        }
        if let Event::WindowEvent { event: WindowEvent::MouseInput { state, button, .. }, .. } = &event {
            lua_engine.lua.globals().get("egui").and_then(|egui_table: mlua::Table| {
                let handler = egui_table.get::<_, mlua::Function>
                    ("mousehandler"
                );
                match handler {
                    Ok(f) => {
                        f.call::<(mlua::Value, mlua::Value), ()>(
                            (
                                mlua::Value::String(lua_engine.lua.create_string(&format!("{:?}", state)).unwrap()),
                                mlua::Value::String(lua_engine.lua.create_string(&format!("{:?}", button)).unwrap()),
                            )
                        ).ok();
                    },
                    Err(_) => { /* no handler registered */ }
                };
                Ok(())
            }).ok();
        }
        if let Event::WindowEvent { event: WindowEvent::CursorMoved { position, .. }, .. } = &event {
            lua_engine.lua.globals().get("egui").and_then(|egui_table: mlua::Table| {
                let handler = egui_table.get::<_, mlua::Function>(
                    "cursorhandler"
                );
                match handler {
                    Ok(f) => {
                        f.call::<(mlua::Value, mlua::Value), ()>(
                            (
                                mlua::Value::Integer(position.x as i64),
                                mlua::Value::Integer(position.y as i64),
                            )
                        ).ok();
                    },
                    Err(_) => { /* no handler registered */ }
                };
                Ok(())
            }).ok();
        }
        match &event {
            Event::WindowEvent { event: WindowEvent::CloseRequested, .. } => {
                *control_flow = ControlFlow::Exit;
            },
            Event::WindowEvent { event: WindowEvent::Resized(size), .. } => {
                config.width = size.width;
                config.height = size.height;
                if config.width > 0 && config.height > 0 {
                    surface.configure(&device, &config);
                }
            },
            _ => {}
        }
        if let Event::WindowEvent { event, .. } = &event {
            let _ = state.on_event(&egui_ctx, event);
        }
        if let Event::MainEventsCleared = event {
            // Luaコルーチンを1フレーム分進める
            unsafe {
                if LUA_THREAD.is_none() {
                    if let Some(ref lua_file) = lua_file {
                        let thread = load_lua_coroutine(&lua_engine.lua, lua_file).expect("Lua coroutineロード失敗");
                        LUA_THREAD = Some(thread);
                    }
                }
                if let Some(ref mut co) = LUA_THREAD {
                    if co.status() == ThreadStatus::Resumable {
                        match co.resume::<(), ()>(()) {
                            Ok(_) => {},
                            Err(e) => {
                                eprintln!("[LuaError] {}", e);
                                // if let mlua::Error::RuntimeError(msg) = &e {
                                //     // Luaエラー時はtracebackも含まれることが多い
                                //     eprintln!("[LuaTraceback]\n{}", msg);
                                // }
                            }
                        };
                    }
                }
            }
            window.request_redraw();
        }
        if let Event::RedrawRequested(_) = event {
            if config.width == 0 || config.height == 0 {
                return;
            }
            let raw_input = state.take_egui_input(&window);
            let full_output = egui_ctx.run(raw_input, |ctx| {
                let windows_lock = windows.lock().unwrap();
                let mut textures = textures.lock().unwrap();
                for w in windows_lock.iter() {
                    let mut w = w.lock().unwrap();
                    let image = ColorImage::from_rgba_unmultiplied([w.width, w.height], &w.buffer);
                    let tex = textures.entry(w.id.clone()).or_insert_with(|| {
                        ctx.load_texture(&w.id, image.clone(), TextureOptions::NEAREST)
                    });
                    tex.set(image, TextureOptions::NEAREST);
                    let inner_response = egui::Window::new(&w.id).show(ctx, |ui| {
                        let size = egui::Vec2::new(w.width as f32, w.height as f32);
                        ui.image(&*tex, size);
                    });
                    if let Some(window_rect) = inner_response.map(|r| r.response.rect) {
                        let pos = window_rect.min;
                        w.x = pos.x as i32;
                        w.y = pos.y as i32;
                    }
                }
            });
            let needs_repaint = full_output.repaint_after.is_zero();
            let clipped_primitives = egui_ctx.tessellate(full_output.shapes);
            let screen_desc = ScreenDescriptor {
                size_in_pixels: [config.width, config.height],
                pixels_per_point: egui_ctx.pixels_per_point(),
            };
            // テクスチャ更新
            for (id, image_delta) in &full_output.textures_delta.set {
                renderer.update_texture(&device, &queue, *id, image_delta);
            }
            for id in &full_output.textures_delta.free {
                renderer.free_texture(id);
            }
            let output_frame = surface.get_current_texture().expect("Failed to acquire next swap chain texture");
            let view = output_frame.texture.create_view(&egui_wgpu::wgpu::TextureViewDescriptor::default());
            let mut encoder = device.create_command_encoder(&egui_wgpu::wgpu::CommandEncoderDescriptor { label: Some("egui encoder") });
            renderer.update_buffers(&device, &queue, &mut encoder, &clipped_primitives, &screen_desc);
            {
                let mut rpass = encoder.begin_render_pass(&egui_wgpu::wgpu::RenderPassDescriptor {
                    label: Some("egui main render pass"),
                    color_attachments: &[Some(egui_wgpu::wgpu::RenderPassColorAttachment {
                        view: &view,
                        resolve_target: None,
                        ops: egui_wgpu::wgpu::Operations {
                            load: egui_wgpu::wgpu::LoadOp::Clear(egui_wgpu::wgpu::Color::BLACK),
                            store: true,
                        },
                    })],
                    depth_stencil_attachment: None,
                });
                renderer.render(&mut rpass, &clipped_primitives, &screen_desc);
            }
            queue.submit(Some(encoder.finish()));
            output_frame.present();
            state.handle_platform_output(&window, &egui_ctx, full_output.platform_output);
            if needs_repaint {
                window.request_redraw();
            }
        }
    });
}
