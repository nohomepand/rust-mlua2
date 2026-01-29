//! midiモジュール（Luaから利用）
//! - midiin, midiout, openinput, openoutput, notein, noteout, send

use midir::{MidiInput, MidiInputConnection, MidiOutput, MidiOutputConnection};
use mlua::{Lua, Result as LuaResult, Table, UserData, UserDataMethods, Value};

// LuaMidiOutputPort: UserData
struct LuaMidiOutputPort {
    conn: MidiOutputConnection,
}
impl UserData for LuaMidiOutputPort {
    fn add_methods<'lua, M: UserDataMethods<'lua, Self>>(methods: &mut M) {
        methods.add_method_mut("notein", |_, this, (note, velocity): (u8, Option<u8>)| {
            let vel = velocity.unwrap_or(0x64);
            this.conn
                .send(&[0x90, note, vel])
                .map_err(|e| mlua::Error::external(e))?;
            Ok(())
        });
        methods.add_method_mut("noteout", |_, this, (note, velocity): (u8, Option<u8>)| {
            let vel = velocity.unwrap_or(0x64);
            this.conn
                .send(&[0x80, note, vel])
                .map_err(|e| mlua::Error::external(e))?;
            Ok(())
        });
        methods.add_method_mut("send", |_, this, args: mlua::Variadic<u8>| {
            this.conn
                .send(&args)
                .map_err(|e| mlua::Error::external(e))?;
            Ok(())
        });
    }
}

pub fn register(lua: &Lua) -> LuaResult<()> {
    let midi_mod = lua.create_table()?;

    // midi.midiin()
    midi_mod.set(
        "midiin",
        lua.create_function(|_, ()| {
            let midi_in = MidiInput::new("mlua-midi-in").map_err(|e| mlua::Error::external(e))?;
            let ports = midi_in.ports();
            let mut names = Vec::new();
            for p in &ports {
                if let Ok(name) = midi_in.port_name(p) {
                    names.push(name);
                }
            }
            Ok(names)
        })?,
    )?;

    // midi.midiout()
    midi_mod.set(
        "midiout",
        lua.create_function(|_, ()| {
            let midi_out =
                MidiOutput::new("mlua-midi-out").map_err(|e| mlua::Error::external(e))?;
            let ports = midi_out.ports();
            let mut names = Vec::new();
            for p in &ports {
                if let Ok(name) = midi_out.port_name(p) {
                    names.push(name);
                }
            }
            Ok(names)
        })?,
    )?;

    // midi.openoutput(name)
    midi_mod.set(
        "openoutput",
        lua.create_function(|lua, name: String| {
            let midi_out =
                MidiOutput::new("mlua-midi-out").map_err(|e| mlua::Error::external(e))?;
            let ports = midi_out.ports();
            for p in &ports {
                if let Ok(port_name) = midi_out.port_name(p) {
                    if port_name == name {
                        let conn = midi_out
                            .connect(p, "mlua-midi-out")
                            .map_err(|e| mlua::Error::external(e))?;
                        let ud = lua.create_userdata(LuaMidiOutputPort { conn })?;
                        return Ok(ud);
                    }
                }
            }
            Err(mlua::Error::external("MIDI output port not found"))
        })?,
    )?;

    // TODO: midi.openinput(name) 実装（受信コールバックは後回し）

    lua.globals().set("midi", midi_mod)?;
    Ok(())
}
