use anyhow::{bail, Context, Result};
use serde::Deserialize;
use std::{collections::HashMap, env, fs};
use syn::visit_mut::{self, VisitMut};
use syn::{Block, Expr, ExprMacro, File, Item, ItemFn, ItemMacro, ItemMod, Macro, Stmt};

#[derive(Deserialize)]
struct ReplacementFile {
    replacements: Vec<Replacement>,
}

#[derive(Deserialize)]
struct Replacement {
    marker: String,
    code: String,
}

fn main() -> Result<()> {
    let mut args = env::args().skip(1);
    let template_path = args.next().context("missing template path")?;
    let replacements_path = args.next().context("missing replacements path")?;
    let out_path = args.next().context("missing output path")?;

    if args.next().is_some() {
        bail!("usage: kiwi-rust-template-patch TEMPLATE REPLACEMENTS_JSON OUT");
    }

    let template = fs::read_to_string(&template_path)
        .with_context(|| format!("failed to read template {template_path}"))?;
    let replacements_json = fs::read_to_string(&replacements_path)
        .with_context(|| format!("failed to read replacements {replacements_path}"))?;
    let replacements_file: ReplacementFile = serde_json::from_str(&replacements_json)
        .with_context(|| format!("failed to parse replacements {replacements_path}"))?;

    let replacements = replacements_file
        .replacements
        .into_iter()
        .map(|replacement| (replacement.marker, replacement.code))
        .collect::<HashMap<_, _>>();

    let mut file = syn::parse_file(&template)
        .with_context(|| format!("failed to parse Rust template {template_path}"))?;
    patch_items(&mut file.items, &replacements)?;

    let formatted = prettyplease::unparse(&file);
    fs::write(&out_path, formatted).with_context(|| format!("failed to write {out_path}"))?;

    Ok(())
}

fn patch_items(items: &mut Vec<Item>, replacements: &HashMap<String, String>) -> Result<()> {
    let mut patched = Vec::with_capacity(items.len());

    for mut item in std::mem::take(items) {
        if let Item::Macro(item_macro) = &item {
            if let Some(code) = replacement_for_macro(&item_macro.mac, replacements) {
                let replacement_file = syn::parse_file(code).with_context(|| {
                    format!(
                        "failed to parse item replacement for {}",
                        macro_path(&item_macro.mac)
                    )
                })?;
                patched.extend(replacement_file.items);
                continue;
            }
        }

        patch_item(&mut item, replacements)?;
        patched.push(item);
    }

    *items = patched;
    Ok(())
}

fn patch_item(item: &mut Item, replacements: &HashMap<String, String>) -> Result<()> {
    match item {
        Item::Mod(item_mod) => patch_mod(item_mod, replacements),
        Item::Fn(item_fn) => patch_fn(item_fn, replacements),
        _ => {
            let mut visitor = MacroReplacementVisitor { replacements };
            visitor.visit_item_mut(item);
            Ok(())
        }
    }
}

fn patch_mod(item_mod: &mut ItemMod, replacements: &HashMap<String, String>) -> Result<()> {
    if let Some((_brace, items)) = &mut item_mod.content {
        patch_items(items, replacements)?;
    }

    Ok(())
}

fn patch_fn(item_fn: &mut ItemFn, replacements: &HashMap<String, String>) -> Result<()> {
    patch_block(&mut item_fn.block, replacements)
}

fn patch_block(block: &mut Block, replacements: &HashMap<String, String>) -> Result<()> {
    let mut patched = Vec::with_capacity(block.stmts.len());

    for mut stmt in std::mem::take(&mut block.stmts) {
        if let Stmt::Macro(stmt_macro) = &stmt {
            if let Some(code) = replacement_for_macro(&stmt_macro.mac, replacements) {
                let replacement_block = parse_replacement_block(code).with_context(|| {
                    format!(
                        "failed to parse statement replacement for {}",
                        macro_path(&stmt_macro.mac)
                    )
                })?;
                patched.extend(replacement_block.stmts);
                continue;
            }
        }

        let mut visitor = MacroReplacementVisitor { replacements };
        visitor.visit_stmt_mut(&mut stmt);
        patched.push(stmt);
    }

    block.stmts = patched;
    Ok(())
}

fn parse_replacement_block(code: &str) -> Result<Block> {
    syn::parse_str::<Block>(code)
        .or_else(|_| syn::parse_str::<Block>(&format!("{{\n{code}\n}}")))
        .context("replacement must be valid Rust statements")
}

struct MacroReplacementVisitor<'a> {
    replacements: &'a HashMap<String, String>,
}

impl VisitMut for MacroReplacementVisitor<'_> {
    fn visit_expr_mut(&mut self, expr: &mut Expr) {
        if let Expr::Macro(ExprMacro { mac, .. }) = expr {
            if let Some(code) = replacement_for_macro(mac, self.replacements) {
                *expr = syn::parse_str::<Expr>(code).unwrap_or_else(|error| {
                    panic!(
                        "failed to parse expression replacement for {}: {error}",
                        macro_path(mac)
                    )
                });
                return;
            }
        }

        visit_mut::visit_expr_mut(self, expr);
    }

    fn visit_block_mut(&mut self, block: &mut Block) {
        if let Err(error) = patch_block(block, self.replacements) {
            panic!("failed to patch block: {error}");
        }
    }
}

fn replacement_for_macro<'a>(
    mac: &Macro,
    replacements: &'a HashMap<String, String>,
) -> Option<&'a str> {
    replacements.get(&macro_path(mac)).map(String::as_str)
}

fn macro_path(mac: &Macro) -> String {
    mac.path
        .segments
        .iter()
        .map(|segment| segment.ident.to_string())
        .collect::<Vec<_>>()
        .join("::")
}
