defmodule KiwiCodec.RustlerGenerator.Splice do
  @moduledoc """
  Static RustQ splice fragments required by generated Rustler decoders.
  """

  @spec rustler_helpers() :: [RustQ.Rust.Fragment.t()]
  def rustler_helpers do
    [decoder_macros()] ++
      RustQ.Rustler.cached_atoms([]) ++
      RustQ.Rustler.term_helpers(
        include: [
          :cached_struct_keys,
          :default_struct_values,
          :make_struct_from_nif_term_arrays
        ]
      )
  end

  defp decoder_macros do
    RustQ.Rust.item(~S'''
    macro_rules! kiwi_enum_decoder {
        (
            fn $name:ident;
            variants [$($value:literal => $atom_name:literal;)*]
        ) => {
            fn $name<'a>(env: Env<'a>, decoder: &mut Decoder<'_>) -> NifResult<Term<'a>> {
                match decoder.read_var_uint()? as i64 {
                    $(
                        $value => Ok(Atom::from_str(env, $atom_name).unwrap().encode(env)),
                    )*
                    value => Ok(value.encode(env)),
                }
            }
        };
    }

    macro_rules! kiwi_struct_decoder {
        (
            fn $name:ident;
            env $env:ident;
            decoder $decoder:ident;
            module_static $module_static:ident;
            keys_static $keys_static:ident;
            module $module_name:literal;
            keys [$($key:literal),* $(,)?];
            fields [$($field_expr:expr),* $(,)?]
        ) => {
            fn $name<'a>($env: Env<'a>, $decoder: &mut Decoder<'_>) -> NifResult<Term<'a>> {
                let module_atom = cached_atom($env, &$module_static, $module_name);
                let keys = cached_struct_keys($env, &$keys_static, &[$($key),*]);
                let mut values = Vec::with_capacity(keys.len());
                values.push(module_atom.as_c_arg());
                $(
                    values.push(($field_expr).encode($env).as_c_arg());
                )*
                make_struct_from_nif_term_arrays($env, keys, &values)
            }
        };
    }

    macro_rules! kiwi_message_decoder {
        (
            fn $decoder_name:ident;
            fields_fn $fields_name:ident;
            env $env:ident;
            decoder $decoder:ident;
            module_static $module_static:ident;
            keys_static $keys_static:ident;
            module $module_name:literal;
            keys [$($key:literal),* $(,)?];
            fields [$($field_id:literal => $index:literal: $field_expr:expr;)*]
        ) => {
            fn $decoder_name<'a>($env: Env<'a>, $decoder: &mut Decoder<'_>) -> NifResult<Term<'a>> {
                let module_atom = cached_atom($env, &$module_static, $module_name);
                let keys = cached_struct_keys($env, &$keys_static, &[$($key),*]);
                let values = default_struct_values($env, module_atom, keys.len() - 1);
                $fields_name($env, $decoder, keys, values)
            }

            fn $fields_name<'a>(
                $env: Env<'a>,
                $decoder: &mut Decoder<'_>,
                keys: &[rustler::wrapper::NIF_TERM],
                mut values: Vec<rustler::wrapper::NIF_TERM>,
            ) -> NifResult<Term<'a>> {
                match $decoder.read_var_uint()? {
                    0 => make_struct_from_nif_term_arrays($env, keys, &values),
                    $(
                        $field_id => {
                            values[$index] = ($field_expr).encode($env).as_c_arg();
                            $fields_name($env, $decoder, keys, values)
                        }
                    )*
                    _unknown => Err(Error::BadArg),
                }
            }
        };
    }

    type KiwiSkipFn = fn(&mut Decoder<'_>) -> NifResult<()>;

    enum KiwiSkipKind {
        One(KiwiSkipFn),
        Repeated(KiwiSkipFn),
        Bytes,
    }

    struct KiwiSkipField {
        id: u32,
        kind: KiwiSkipKind,
    }

    fn kiwi_skip_bool_value(decoder: &mut Decoder<'_>) -> NifResult<()> {
        decoder.read_bool()?;
        Ok(())
    }

    fn kiwi_skip_byte_value(decoder: &mut Decoder<'_>) -> NifResult<()> {
        decoder.read_byte()?;
        Ok(())
    }

    fn kiwi_skip_float_value(decoder: &mut Decoder<'_>) -> NifResult<()> {
        decoder.read_var_float_value()?;
        Ok(())
    }

    fn kiwi_skip_int_value(decoder: &mut Decoder<'_>) -> NifResult<()> {
        decoder.read_var_int()?;
        Ok(())
    }

    fn kiwi_skip_int64_value(decoder: &mut Decoder<'_>) -> NifResult<()> {
        decoder.read_var_int64()?;
        Ok(())
    }

    fn kiwi_skip_string_value(decoder: &mut Decoder<'_>) -> NifResult<()> {
        decoder.skip_string()?;
        Ok(())
    }

    fn kiwi_skip_uint_value(decoder: &mut Decoder<'_>) -> NifResult<()> {
        decoder.read_var_uint()?;
        Ok(())
    }

    fn kiwi_skip_uint64_value(decoder: &mut Decoder<'_>) -> NifResult<()> {
        decoder.read_var_uint64()?;
        Ok(())
    }

    fn kiwi_skip_bytes_value(decoder: &mut Decoder<'_>) -> NifResult<()> {
        decoder.skip_byte_array()?;
        Ok(())
    }

    fn kiwi_skip_repeated(decoder: &mut Decoder<'_>, item: KiwiSkipFn) -> NifResult<()> {
        decoder.read_repeated(|decoder| item(decoder))?;
        Ok(())
    }

    fn kiwi_skip_kind(decoder: &mut Decoder<'_>, kind: &KiwiSkipKind) -> NifResult<()> {
        match kind {
            KiwiSkipKind::One(skip) => skip(decoder),
            KiwiSkipKind::Repeated(skip) => kiwi_skip_repeated(decoder, *skip),
            KiwiSkipKind::Bytes => kiwi_skip_bytes_value(decoder),
        }
    }

    fn kiwi_skip_struct_fields(decoder: &mut Decoder<'_>, fields: &[KiwiSkipKind]) -> NifResult<()> {
        for kind in fields {
            kiwi_skip_kind(decoder, kind)?;
        }
        Ok(())
    }

    fn kiwi_skip_message_fields(
        decoder: &mut Decoder<'_>,
        definition_name: &str,
        fields: &[KiwiSkipField],
    ) -> NifResult<()> {
        loop {
            match decoder.read_var_uint()? {
                0 => break,
                field_id => match fields.iter().find(|field| field.id == field_id) {
                    Some(field) => kiwi_skip_kind(decoder, &field.kind)?,
                    None => {
                        return Err(Error::Term(Box::new(format!(
                            "unknown field {} while skipping {}",
                            field_id,
                            definition_name
                        ))));
                    }
                },
            }
        }
        Ok(())
    }

    #[allow(unused_macros)]
    macro_rules! kiwi_sparse_enum_decoder {
        (
            fn $name:ident;
            env $env:ident;
            decoder $decoder:ident;
            variants [$($value:literal => $atom_name:literal;)*]
        ) => {
            fn $name<'a>($env: Env<'a>, $decoder: &mut Decoder<'_>) -> NifResult<Term<'a>> {
                match $decoder.read_var_uint()? as i64 {
                    $(
                        $value => Ok(Atom::from_str($env, $atom_name).unwrap().encode($env)),
                    )*
                    value => Ok(value.encode($env)),
                }
            }
        };
    }

    macro_rules! kiwi_sparse_struct_decoder {
        (
            fn $name:ident;
            env $env:ident;
            decoder $decoder:ident;
            module $module_name:literal;
            capacity $capacity:literal;
            fields [$($field_name:literal: $field_expr:expr;)*]
        ) => {
            fn $name<'a>($env: Env<'a>, $decoder: &mut Decoder<'_>) -> NifResult<Term<'a>> {
                let module_atom = Atom::from_str($env, $module_name).unwrap();
                let module_key_atom = Atom::from_str($env, "__kiwi_module__").unwrap();
                let mut keys = Vec::with_capacity($capacity);
                let mut values = Vec::with_capacity($capacity);
                keys.push(module_key_atom.encode($env));
                values.push(module_atom.encode($env));
                $(
                    keys.push(Atom::from_str($env, $field_name).unwrap().encode($env));
                    values.push($field_expr);
                )*
                Term::map_from_term_arrays($env, &keys, &values)
            }
        };
    }

    macro_rules! kiwi_sparse_message_decoder {
        (
            fn $name:ident;
            env $env:ident;
            decoder $decoder:ident;
            module $module_name:literal;
            definition $definition_name:literal;
            capacity $capacity:literal;
            fields [$($field_id:literal => $field_name:literal: $field_expr:expr;)*]
        ) => {
            fn $name<'a>($env: Env<'a>, $decoder: &mut Decoder<'_>) -> NifResult<Term<'a>> {
                let module_atom = Atom::from_str($env, $module_name).unwrap();
                let module_key_atom = Atom::from_str($env, "__kiwi_module__").unwrap();
                let mut keys = Vec::with_capacity($capacity);
                let mut values = Vec::with_capacity($capacity);
                keys.push(module_key_atom.encode($env));
                values.push(module_atom.encode($env));
                loop {
                    match $decoder.read_var_uint()? {
                        0 => break,
                        $(
                            $field_id => {
                                keys.push(Atom::from_str($env, $field_name).unwrap().encode($env));
                                values.push($field_expr);
                            }
                        )*
                        field => {
                            return Err(Error::Term(Box::new(format!(
                                "unknown field {} while decoding sparse {}",
                                field,
                                $definition_name
                            ))));
                        }
                    }
                }
                Term::map_from_term_arrays($env, &keys, &values)
            }
        };
    }
    ''')
  end
end
