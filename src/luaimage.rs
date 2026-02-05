use crate::luagraphic;
use mlua::{UserData, UserDataMethods, Lua, Result as LuaResult, Value};
use image::{DynamicImage, GenericImageView, ImageBuffer, RgbaImage};
use std::path::Path;

pub struct LuaImage {
    pub img: DynamicImage,
}

impl UserData for LuaImage {
    fn add_methods<'lua, M: UserDataMethods<'lua, Self>>(methods: &mut M) {
        // save: img:save(filepath)
        methods.add_method_mut("save", |_, this, filepath: String| {
            this.img.save(&filepath).map_err(mlua::Error::external)?;
            Ok(())
        });
        // crop: img:crop(x, y, w, h) -> 新しいLuaImage
        methods.add_method("crop", |_, this, (x, y, w, h): (u32, u32, u32, u32)| {
            let sub = this.img.crop_imm(x, y, w, h);
            Ok(LuaImage { img: sub })
        });
        // subimage: img:subimage(sx, sy, width, height) -> 新しいLuaImage
        methods.add_method("subimage", |_, this, (sx, sy, width, height): (u32, u32, u32, u32)| {
            let sub = this.img.view(sx, sy, width, height).to_image();
            Ok(LuaImage { img: DynamicImage::ImageRgba8(sub) })
        });
        methods.add_method("getwidth", |_, this, ()| {
            Ok(this.img.width())
        });
        methods.add_method("getheight", |_, this, ()| {
            Ok(this.img.height())
        });
        methods.add_method("tographic", |lua, this, ()| {
            let raw = this.img.to_rgba8().into_raw().into_boxed_slice();
            let g = luagraphic::RGBABufferBase::new(
                this.img.width() as usize,
                this.img.height() as usize,
                Some(&raw)
            );
            Ok(lua.create_userdata(g)?)
        });
    }
}

pub fn register_lua_image(lua: &Lua) -> LuaResult<()> {
    let image_mod = lua.create_table()?;
    image_mod.set("load", lua.create_function(|lua, filepath: String| {
        let img = image::open(&Path::new(&filepath)).map_err(mlua::Error::external)?;
        let ud = lua.create_userdata(LuaImage { img })?;
        Ok(ud)
    })?)?;
    lua.globals().set("image", image_mod)?;
    Ok(())
}

// capture, drawimageはLuaWindow側で実装
