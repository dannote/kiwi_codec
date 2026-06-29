defmodule KiwiCodec.RustlerGenerator.Splice do
  @moduledoc """
  Static RustQ splice fragments required by generated Rustler decoders.

  The Rust source below is an intentional escape boundary: generated schema code
  targets these compact Rust macros so high-level Elixir generators can stay
  semantic without expanding large repetitive Rust bodies.
  """

  alias KiwiCodec.RustlerGenerator.SkipHelpers
  alias KiwiCodec.RustlerGenerator.SparseHelpers
  alias RustQ.Rust.AST.Builder, as: A

  @spec rustler_helpers(keyword()) :: [RustQ.Rust.Fragment.t()]
  def rustler_helpers(opts \\ []) do
    features = Keyword.get(opts, :features, [:full])
    decoder_sources = helper_decoder_sources(opts, features)

    decoder_macros(features, decoder_sources, opts) ++
      RustQ.Rustler.cached_atoms([]) ++
      RustQ.Rustler.term_helpers(
        include: [
          :cached_struct_keys,
          :default_struct_values,
          :make_struct_from_nif_term_arrays
        ]
      )
  end

  defp helper_decoder_sources(opts, features) do
    if Enum.any?(features, &(&1 in [:skip, :sparse])) do
      Keyword.get(opts, :decoder_sources, [])
    else
      []
    end
  end

  defp decoder_macros(features, decoder_sources, opts) do
    [
      if(:full in features, do: RustQ.Rust.item(full_decoder_macros()), else: []),
      if(:skip in features, do: skip_decoder_fragments(decoder_sources), else: []),
      if(:sparse in features,
        do: sparse_decoder_fragments(decoder_sources, shared_sparse_skip?(features, opts)),
        else: []
      )
    ]
    |> List.flatten()
  end

  defp full_decoder_macros do
    ~S'''
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
    '''
  end

  defp skip_decoder_fragments([]), do: [RustQ.Rust.item(skip_decoder_helpers())]

  defp skip_decoder_fragments(decoder_sources) do
    [
      RustQ.Rust.item(skip_decoder_kind_type()),
      SkipHelpers.fragments(decoder_sources),
      RustQ.Rust.item(skip_decoder_dispatch(message_fields?: false))
    ]
  end

  defp skip_decoder_types do
    [
      ~S'''
      type KiwiSkipFn = fn(&mut Decoder<'_>) -> NifResult<()>;
      ''',
      skip_decoder_kind_type(),
      ~S'''
      struct KiwiSkipField {
          id: u32,
          kind: KiwiSkipKind,
      }
      '''
    ]
  end

  defp skip_decoder_kind_type do
    ~S'''
    #[derive(Clone, Debug)]
    pub enum KiwiSkipKind {
        One(KiwiSkipFn),
        Repeated(KiwiSkipFn),
        Bytes,
    }
    '''
  end

  defp skip_decoder_helpers do
    [
      skip_decoder_types(),
      "\n",
      raw_skip_value_helpers(),
      "\n",
      skip_decoder_dispatch(message_fields?: true)
    ]
  end

  defp raw_skip_value_helpers do
    ~S'''
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
    '''
  end

  defp skip_decoder_dispatch(opts) do
    message_fields? = Keyword.fetch!(opts, :message_fields?)

    [
      skip_decoder_dispatch_base(),
      if(message_fields?, do: skip_message_fields_dispatch(), else: []),
      skip_decoder_macros()
    ]
  end

  defp skip_decoder_dispatch_base do
    ~S'''
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

    '''
  end

  defp skip_message_fields_dispatch do
    ~S'''
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
    '''
  end

  defp skip_decoder_macros do
    ~S'''
    macro_rules! kiwi_skip_decode {
        (bool) => { kiwi_skip_bool_value };
        (byte) => { kiwi_skip_byte_value };
        (float) => { kiwi_skip_float_value };
        (int) => { kiwi_skip_int_value };
        (int64) => { kiwi_skip_int64_value };
        (string) => { kiwi_skip_string_value };
        (uint) => { kiwi_skip_uint_value };
        (uint64) => { kiwi_skip_uint64_value };
        (bytes) => { kiwi_skip_bytes_value };
        ($skip:ident) => { $skip };
    }

    macro_rules! kiwi_skip_kind {
        (one $skip:ident) => { KiwiSkipKind::One($skip) };
        (repeated $skip:ident) => { KiwiSkipKind::Repeated($skip) };
        (bytes $skip:ident) => { KiwiSkipKind::Bytes };
        (one, $skip:expr) => { KiwiSkipKind::One($skip) };
        (repeated, $skip:expr) => { KiwiSkipKind::Repeated($skip) };
        (bytes, $skip:expr) => { KiwiSkipKind::Bytes };
    }

    macro_rules! kiwi_skip_struct_decoder {
        (fn $name:ident; decoder $decoder:ident; fields [$($field_mode:ident $field_skip:ident;)*]) => {
            fn $name($decoder: &mut Decoder<'_>) -> NifResult<()> {
                kiwi_skip_struct_fields($decoder, &[$(kiwi_skip_kind!($field_mode $field_skip),)*])
            }
        };
    }

    #[allow(unused_macros)]
    macro_rules! kiwi_skip_message_decoder {
        (
            fn $name:ident;
            decoder $decoder:ident;
            definition $definition_name:literal;
            fields [$($field_id:literal => $field_mode:ident $field_skip:ident;)*]
        ) => {
            fn $name($decoder: &mut Decoder<'_>) -> NifResult<()> {
                kiwi_skip_message_fields(
                    $decoder,
                    $definition_name,
                    &[$(KiwiSkipField { id: $field_id, kind: kiwi_skip_kind!($field_mode $field_skip) },)*],
                )
            }
        };
    }
    '''
  end

  defp shared_sparse_skip?(features, opts) do
    :sparse in features and :skip in features and
      Keyword.get(opts, :sparse_messages, :match) == :descriptor
  end

  defp sparse_decoder_fragments(decoder_sources, shared?)

  defp sparse_decoder_fragments([], _shared?) do
    [
      RustQ.Rust.item([sparse_decoder_declarations(), "\n", raw_sparse_value_helpers()]),
      sparse_descriptor_macros(),
      RustQ.Rust.item(sparse_message_decoder_macro())
    ]
  end

  defp sparse_decoder_fragments(decoder_sources, shared?) do
    [
      RustQ.Rust.item(sparse_decoder_declarations()),
      sparse_repeated_macro_fragment(),
      SparseHelpers.fragments(decoder_sources, macros: sparse_helper_macros(shared?)),
      RustQ.Rust.item(sparse_message_decoder_macro())
    ]
  end

  defp sparse_decoder_declarations do
    ~S'''
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

    macro_rules! kiwi_sparse_decode {
        (bool) => { kiwi_sparse_bool_value };
        (byte) => { kiwi_sparse_byte_value };
        (float) => { kiwi_sparse_float_value };
        (int) => { kiwi_sparse_int_value };
        (int64) => { kiwi_sparse_int64_value };
        (string) => { kiwi_sparse_string_value };
        (uint) => { kiwi_sparse_uint_value };
        (uint64) => { kiwi_sparse_uint64_value };
        (bytes) => { kiwi_sparse_bytes_value };
        ($decode:ident) => { $decode };
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

    '''
  end

  defp raw_sparse_value_helpers do
    ~S'''
    fn kiwi_sparse_bool_value<'a>(env: Env<'a>, decoder: &mut Decoder<'_>) -> NifResult<Term<'a>> {
        Ok(decoder.read_bool()?.encode(env))
    }

    fn kiwi_sparse_byte_value<'a>(env: Env<'a>, decoder: &mut Decoder<'_>) -> NifResult<Term<'a>> {
        Ok(decoder.read_byte()?.encode(env))
    }

    fn kiwi_sparse_float_value<'a>(env: Env<'a>, decoder: &mut Decoder<'_>) -> NifResult<Term<'a>> {
        decoder.read_var_float(env)
    }

    fn kiwi_sparse_int_value<'a>(env: Env<'a>, decoder: &mut Decoder<'_>) -> NifResult<Term<'a>> {
        Ok(decoder.read_var_int()?.encode(env))
    }

    fn kiwi_sparse_int64_value<'a>(env: Env<'a>, decoder: &mut Decoder<'_>) -> NifResult<Term<'a>> {
        Ok(decoder.read_var_int64()?.encode(env))
    }

    fn kiwi_sparse_string_value<'a>(env: Env<'a>, decoder: &mut Decoder<'_>) -> NifResult<Term<'a>> {
        decoder.read_string(env)
    }

    fn kiwi_sparse_uint_value<'a>(env: Env<'a>, decoder: &mut Decoder<'_>) -> NifResult<Term<'a>> {
        Ok(decoder.read_var_uint()?.encode(env))
    }

    fn kiwi_sparse_uint64_value<'a>(env: Env<'a>, decoder: &mut Decoder<'_>) -> NifResult<Term<'a>> {
        Ok(decoder.read_var_uint64()?.encode(env))
    }

    fn kiwi_sparse_bytes_value<'a>(env: Env<'a>, decoder: &mut Decoder<'_>) -> NifResult<Term<'a>> {
        decoder.read_byte_array(env)
    }
    '''
  end

  defp sparse_helper_macros(true), do: [:kiwi_sparse_skip_message_descriptor_decoder]
  defp sparse_helper_macros(false), do: [:kiwi_sparse_message_descriptor_decoder]

  defp sparse_descriptor_macros do
    [
      sparse_repeated_macro_fragment(),
      "\n",
      RustQ.Rust.to_fragment(sparse_message_descriptor_macro())
    ]
  end

  defp sparse_repeated_macro_fragment, do: RustQ.Rust.to_fragment(sparse_repeated_macro())

  defp sparse_repeated_macro do
    A.macro_rules(
      :kiwi_sparse_repeated,
      [
        A.macro_rule(["one"], ["false"]),
        A.macro_rule(["repeated"], ["true"])
      ],
      attrs: [A.allow_attr(:unused_macros)]
    )
  end

  defp sparse_message_descriptor_macro do
    A.macro_rules(
      :kiwi_sparse_message_descriptor_decoder,
      A.macro_rule(
        [
          "fn ",
          A.macro_var(:name, :ident),
          ";\n            env ",
          A.macro_var(:env, :ident),
          ";\n            decoder ",
          A.macro_var(:decoder, :ident),
          ";\n            module ",
          A.macro_var(:module_name, :literal),
          ";\n            definition ",
          A.macro_var(:definition_name, :literal),
          ";\n            capacity ",
          A.macro_var(:capacity, :literal),
          ";\n            fields [",
          A.macro_repeat([
            A.macro_var(:field_id, :literal),
            " => ",
            A.macro_var(:field_name, :literal),
            ": ",
            A.macro_var(:field_mode, :ident),
            " ",
            A.macro_var(:field_decode, :ident),
            ";"
          ]),
          "]"
        ],
        [
          "fn ",
          A.macro_capture(:name),
          "<'a>(",
          A.macro_capture(:env),
          ": Env<'a>, ",
          A.macro_capture(:decoder),
          ": &mut Decoder<'_>) -> NifResult<Term<'a>> {\n",
          "    kiwi_sparse_message_fields(\n",
          "        ",
          A.macro_capture(:env),
          ",\n",
          "        ",
          A.macro_capture(:decoder),
          ",\n",
          "        ",
          A.macro_capture(:module_name),
          ",\n",
          "        ",
          A.macro_capture(:definition_name),
          ",\n",
          "        ",
          A.macro_capture(:capacity),
          ",\n",
          "        &[",
          A.macro_repeat([
            "KiwiSparseField { id: ",
            A.macro_capture(:field_id),
            ", name: ",
            A.macro_capture(:field_name),
            ", repeated: kiwi_sparse_repeated!(",
            A.macro_capture(:field_mode),
            "), decode: ",
            A.macro_capture(:field_decode),
            " },"
          ]),
          "],\n",
          "    )\n",
          "}"
        ]
      ),
      attrs: [A.allow_attr(:unused_macros)]
    )
  end

  defp sparse_message_decoder_macro do
    ~S'''
    #[allow(unused_macros)]
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
    '''
  end
end
