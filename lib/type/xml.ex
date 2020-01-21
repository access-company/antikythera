# Copyright(c) 2015-2020 ACCESS CO., LTD. All rights reserved.

use Croma

defmodule Antikythera.Xml do
  el = inspect(__MODULE__.Element)
  @moduledoc """
  Convenient XML parser module wrapping [fast_xml](https://github.com/processone/fast_xml).

  `decode/2` can parse XML into `#{el}.t`, and `encode/2` can serialize `#{el}.t` back to XML string.

  `#{el}.t` is XML element data structure, and it is JSON-convertible struct.
  You can safely convert them to JSON using `Poison.encode/2` while keeping order of appearance of children,
  and also convert them back to `#{el}.t` with `Poison.decode/2` and `#{el}.new/1`.

  Note that order of attributes will not be preserved, since it is not significant.
  See [here](https://www.w3.org/TR/xml/#sec-starttags)

  Namespace of tags (e.g. "ns" in `<ns:tag>`) are kept as is in `:name` of elements.

  Namespace definitions (e.g. `xmlns:ns='http://example.com/ns'`) are treated as plain attributes,
  and kept as is in `:attributes` of elements.

  ## `Access` behaviour

  `#{el}` implements `Access` behaviour for convenient lookups and updates.
  Following access patterns are available:

  - `element[:name]`, `element[:attributes]`, `element[:children]`
      - Fetch values of fields in dynamic lookup style.
  - `element["@some_attr"]`
      - Fetch value of "some_attr" in `:attributes` map.
  - `element[:texts]`
      - Fetch text (character data) children. It always returns list.
  - `element["some_name"]`
      - Fetch child elements with `name: "some_name"`. It always returns list.

  You can also use these patterns in `Kernel.get_in/2` and its variants.

      iex> xml = "<a>foo<b>bar</b>baz</a>"
      iex> element = #{inspect(__MODULE__)}.decode!(xml)
      %#{el}{name: "a", attributes: %{}, children: [
        "foo",
        %#{el}{name: "b", attributes: %{}, children: ["bar"]},
        "baz",
      ]}
      iex> get_in(element, [:texts])
      ["foo", "baz"]
      iex> get_in(element, ["b", Access.at(0), :texts])
      ["bar"]
      iex> get_and_update_in(element, [:children, Access.at(0)], fn _ -> :pop end)
      {"foo",
      %#{el}{name: "a", attributes: %{}, children: [
        %#{el}{name: "b", attributes: %{}, children: ["bar"]},
        "baz",
      ]}}
      iex> update_in(element, [:children, Access.all()], fn
      ...>   text when is_binary(text) -> %#{el}{name: "b", attributes: %{}, children: [text]}
      ...>   e -> e
      ...> end)
      %#{el}{name: "a", attributes: %{}, children: [
        %#{el}{name: "b", attributes: %{}, children: ["foo"]},
        %#{el}{name: "b", attributes: %{}, children: ["bar"]},
        %#{el}{name: "b", attributes: %{}, children: ["baz"]},
      ]}
      iex> update_in(element, ["@id"], fn _ -> "001" end)
      %#{el}{name: "a", attributes: %{"id" => "001"}, children: [
        "foo",
        %#{el}{name: "b", attributes: %{}, children: ["bar"]},
        "baz",
      ]}

  Notes on updating with `Kernel.get_and_update_in/3` and its variants:

  - Struct fields are static and cannot be popped.
  - Custom access keys except "@some_attr" cannot be used in updating.
    Use `:children` instead, in order to update children while preserving order of appearance.
  """

  alias Croma.Result, as: R

  defmodule Content do
    alias Antikythera.Xml.Element

    @type t :: String.t | Element.t

    defun valid?(v :: term) :: boolean do
      is_binary(v) or Element.valid?(v)
    end

    defun new(v :: term) :: R.t(t) do
      s when is_binary(s) -> {:ok, s}
      m when is_map(m)    -> Element.new(m)
      _                   -> {:error, {:invalid_value, [__MODULE__]}}
    end
  end

  defmodule Element do
    use Croma.Struct, recursive_new?: true, fields: [
      name:       Croma.String,
      attributes: Croma.Map,
      children:   Croma.TypeGen.list_of(Content),
    ]

    @behaviour Access

    # Access behaviour implementations

    @impl true
    def fetch(%__MODULE__{name: n}      , :name           )                    , do: {:ok, n}
    def fetch(%__MODULE__{attributes: a}, :attributes     )                    , do: {:ok, a}
    def fetch(%__MODULE__{children: c}  , :children       )                    , do: {:ok, c}
    def fetch(%__MODULE__{attributes: a}, "@" <> attribute)                    , do: Map.fetch(a, attribute)
    def fetch(%__MODULE__{children: c}  , :texts          )                    , do: {:ok, Enum.filter(c, &is_binary/1)}
    def fetch(%__MODULE__{children: c}  , key             ) when is_binary(key), do: {:ok, Enum.filter(c, &has_name?(&1, key))}
    def fetch(%__MODULE__{}             , _               )                    , do: :error

    defp has_name?(%__MODULE__{name: n}, n), do: true
    defp has_name?(_, _), do: false

    @impl true
    def get_and_update(%__MODULE__{} = e, key, f) when key in [:name, :attributes, :children] do
      case e |> Map.fetch!(key) |> f.() do
        {get_value, new_value} -> {get_value, update_struct_field(e, key, new_value)}
        :pop                   -> raise "Cannot pop struct field!"
      end
    end
    def get_and_update(%__MODULE__{attributes: as} = e, "@" <> attribute, f) do
      current_value = Map.get(as, attribute)
      case f.(current_value) do
        {get_value, new_attr} when is_binary(new_attr) -> {get_value    , %__MODULE__{e | attributes: Map.put(as, attribute, new_attr)}}
        :pop                                           -> {current_value, %__MODULE__{e | attributes: Map.delete(as, attribute)}}
      end
    end
    def get_and_update(_e, key, _f) do
      raise ~s[#{inspect(__MODULE__)}.get_and_update/3 only accepts :name, :attributes, :children or "@attribute" as key for updating, got: #{inspect(key)}]
    end

    defp update_struct_field(%__MODULE__{} = e, :name      , new_name    ) when is_binary(new_name)  , do: %__MODULE__{e | name: new_name}
    defp update_struct_field(%__MODULE__{} = e, :attributes, new_attrs   ) when is_map(new_attrs)    , do: %__MODULE__{e | attributes: new_attrs}
    defp update_struct_field(%__MODULE__{} = e, :children  , new_children) when is_list(new_children), do: %__MODULE__{e | children: new_children}

    @impl true
    def pop(element, key) do
      get_and_update(element, key, fn _ -> :pop end)
    end
  end

  @type decode_option :: {:trim, boolean}

  @doc """
  Reads an XML string and parses it into `#{el}.t`.

  Comments and header will be discarded.

  It can read XHTML document as long as they are well-formatted,
  though it does not understand Document Type Definition (DTD, header line with "<!DOCTYPE html PUBLIC ..."),
  so you must remove them.

  It tries to read a document with UTF-8 encoding, regardless of "encoding" attribute in the header.

  Options:

  - `:trim` - Drop whitespace-only texts. Default `false`.
      - There are no universal way to distinguish significant and insignificant whitespaces,
        so this option may alter the meaning of original document. Use with caution.
      - In [W3C recommendation](https://www.w3.org/TR/REC-xml/#sec-white-space),
        it is stated that whitespace texts (character data) are basically significant and must be preserved.
  """
  defun decode(xml_string :: v[String.t], opts :: v[[decode_option]] \\ []) :: R.t(Element.t) do
    case :fxml_stream.parse_element(xml_string) do
      {:error, _} = e -> e
      record          -> from_record(record, Keyword.get(opts, :trim, false)) |> R.wrap_if_valid(Element)
    end
  end

  defunp from_record({:xmlel, name, attrs, children} :: :fxml.xmlel, trim :: v[boolean]) :: Element.t do
    %Element{
      name:       name,
      attributes: Map.new(attrs),
      children:   children(children, trim, []),
    }
  end

  defp children([]                             , _   , acc), do: Enum.reverse(acc)
  defp children([{:xmlcdata, text} | tail]     , true, acc), do: children(tail, true , cons_trimmed(text, acc))
  defp children([{:xmlcdata, text} | tail]     , _   , acc), do: children(tail, false, [text | acc])
  defp children([{:xmlel, _, _, _} = el | tail], trim, acc), do: children(tail, trim , [from_record(el, trim) | acc])

  defp cons_trimmed(text, acc) do
    case String.trim(text) do
      "" -> acc          # Nothing other than whitespaces; must be indents
      _  -> [text | acc] # Otherwise, keep leading/trailing whitespaces since they may have meanings
    end
  end

  @xml_header ~S(<?xml version='1.0' encoding='UTF-8'?>)

  @type encode_option :: {:pretty | :with_header, boolean}

  @doc """
  Serializes `#{el}.t` into XML string.

  Specifications:

  - Trailing newline will not be generated.
  - All single- and double-quotations in attribute values or entity values are escaped to
    `&apos;` and `&quot;` respectively.
  - All attribute values are SINGLE-quoted.
  - Does not insert a whitespace before "/>" in element without children.

  Options:

  - `:pretty` - Pretty print with 2-space indents. Default `false`.
      - Similar to `:trim` option in `decode/2`, inserted whitespaces may be significant,
        thus it can alter meaning of original document. Use with caution.
      - It does not insert whitespaces to elements with [mixed-content](https://www.w3.org/TR/REC-xml/#sec-mixed-content)
        and their descendants, in order to reduce probability to alter the meaning of original document.
  - `:with_header` - Prepend `#{@xml_header}\\n`. Default `false`.
  """
  defun encode(xml_element :: v[Element.t], opts :: v[[encode_option]] \\ []) :: String.t do
    body = xml_element |> to_record(Keyword.get(opts, :pretty, false), 0) |> :fxml.element_to_binary()
    case opts[:with_header] do
      true -> "#{@xml_header}\n" <> body
      _    -> body
    end
  end

  defunp to_record(content :: Content.t, pretty? :: boolean, level :: non_neg_integer) :: :fxml.xmlel do
    (%Element{name: n, attributes: a, children: c}, true, level) -> {:xmlel, n, Map.to_list(a), prettified_children(c, level)}
    (%Element{name: n, attributes: a, children: c}, _   , _    ) -> {:xmlel, n, Map.to_list(a), Enum.map(c, &to_record(&1, false, 0))}
    (text, _, _) when is_binary(text)                            -> {:xmlcdata, text}
  end

  defp prettified_children([]      , _level),                      do: []
  defp prettified_children([text]  , _level) when is_binary(text), do: [{:xmlcdata, text}] # If there is only a single text child, directly produce non-prettified record
  defp prettified_children(children,  level),                      do: map_to_record_and_interleave_whitespaces(children, level)

  @indent_unit "  "

  defp map_to_record_and_interleave_whitespaces(children, level) do
    {children, mixed?} = map_to_record(children, level)
    interleave_whitespaces(children, level, mixed?)
  end

  defp map_to_record(children, level) do
    Enum.map_reduce(children, false, fn
      (text, _mixed?) when is_binary(text) -> {{:xmlcdata, text}               , true  }
      (%Element{} = e, mixed?)             -> {to_record(e, !mixed?, level + 1), mixed?}
    end)
  end

  defp interleave_whitespaces(children, _level, true ), do: children
  defp interleave_whitespaces(children,  level, false) do
    child_indent     = {:xmlcdata, "\n" <> String.duplicate(@indent_unit, level + 1)}
    close_tag_indent = {:xmlcdata, "\n" <> String.duplicate(@indent_unit, level)}
    Enum.flat_map(children, &[child_indent, &1]) ++ [close_tag_indent]
  end

  R.define_bang_version_of([decode: 1, decode: 2])
end
