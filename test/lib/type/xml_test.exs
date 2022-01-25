# Copyright(c) 2015-2022 ACCESS CO., LTD. All rights reserved.

defmodule Antikythera.XmlTest do
  use Croma.TestCase
  alias Xml.Element, as: E
  doctest Xml

  # Taken from https://www.w3schools.com/xml/xml_examples.asp and apostrophe escaped (for testing purpose)
  @note_xml ~S{<?xml version='1.0' encoding='UTF-8'?>
<note>
  <to>Tove</to>
  <from>Jani</from>
  <heading>Reminder</heading>
  <body>Don&apos;t forget me this weekend!</body>
</note>}
  # Taken from https://msdn.microsoft.com/en-us/library/ms762271
  @books_xml File.read!(Path.expand("books.xml", __DIR__))

  test "should decode and encode XML while keeping its information through JSON serialization" do
    note_xml = Xml.decode!(@note_xml)
    assert note_xml |> Xml.encode(with_header: true) == @note_xml

    assert note_xml
           |> Poison.encode!()
           |> Poison.decode!()
           |> E.new!()
           |> Xml.encode(with_header: true) == @note_xml

    trimmed_note_xml = Xml.decode!(@note_xml, trim: true)
    assert trimmed_note_xml |> Xml.encode(pretty: true, with_header: true) == @note_xml

    assert trimmed_note_xml
           |> Poison.encode!()
           |> Poison.decode!()
           |> E.new!()
           |> Xml.encode(pretty: true, with_header: true) == @note_xml
  end

  test "should correctly pretty print XML without inserting whitespaces into elements with mixed-content" do
    xml0 = Xml.decode!("<a>foo<b>bar</b>baz</a>")
    assert Xml.encode(xml0, pretty: true) == "<a>foo<b>bar</b>baz</a>"
    xml1 = Xml.decode!("<a><b>foo</b><b>bar<c>baz</c></b><b><d>ban</d></b></a>")

    assert Xml.encode(xml1, pretty: true) <> "\n" ==
             """
             <a>
               <b>foo</b>
               <b>bar<c>baz</c></b>
               <b>
                 <d>ban</d>
               </b>
             </a>
             """
  end

  test "should unescape escaped string on decode" do
    xml0 = Xml.decode!("<body>Don&apos;t forget me this weekend!</body>")
    assert xml0.children == ["Don't forget me this weekend!"]

    # Can also read unescaped apostrophe; only `<` and `&` are strictly required to be escaped in XML documents
    assert Xml.decode!("<body>Don't forget me this weekend!</body>") == xml0
    assert Xml.decode("<truth>0 < 42</truth>") |> Croma.Result.error?()
  end

  test "should accept Access lookups/updates" do
    note_xml = Xml.decode!(@note_xml, trim: true)
    assert note_xml[:name] == "note"
    assert note_xml[:attributes] == %{}
    assert length(note_xml[:children]) == 4
    [note0] = note_xml["to"]
    assert note0 == %E{name: "to", attributes: %{}, children: ["Tove"]}
    assert note0[:texts] == ["Tove"]

    assert get_in(note_xml, [:children, Access.all(), :texts]) == [
             ["Tove"],
             ["Jani"],
             ["Reminder"],
             ["Don't forget me this weekend!"]
           ]

    books_xml = Xml.decode!(@books_xml, trim: true)
    assert books_xml[:name] == "catalog"
    assert length(books_xml["book"]) == 12

    assert get_in(books_xml, ["book", Access.at(0)]) ==
             %E{
               name: "book",
               attributes: %{"id" => "bk101"},
               children: [
                 %E{name: "author", attributes: %{}, children: ["Gambardella, Matthew"]},
                 %E{name: "title", attributes: %{}, children: ["XML Developer's Guide"]},
                 %E{name: "genre", attributes: %{}, children: ["Computer"]},
                 %E{name: "price", attributes: %{}, children: ["44.95"]},
                 %E{name: "publish_date", attributes: %{}, children: ["2000-10-01"]},
                 %E{
                   name: "description",
                   attributes: %{},
                   children: ["An in-depth look at creating applications \n      with XML."]
                 }
               ]
             }

    assert get_in(books_xml, ["book", Access.all(), "genre", Access.at(0), :texts, Access.at(0)])
           |> Enum.uniq() == ["Computer", "Fantasy", "Romance", "Horror", "Science Fiction"]

    {get_value, updated_xml} =
      get_and_update_in(
        books_xml,
        [:children, Access.all(), :children, Access.at(2), :children, Access.at(0)],
        &{&1, String.upcase(&1)}
      )

    assert Enum.uniq(get_value) == ["Computer", "Fantasy", "Romance", "Horror", "Science Fiction"]

    assert get_in(updated_xml, ["book", Access.all(), "genre", Access.at(0), :texts, Access.at(0)])
           |> Enum.uniq() == ["COMPUTER", "FANTASY", "ROMANCE", "HORROR", "SCIENCE FICTION"]
  end

  test "should handle attributes with nested quotations" do
    assert Xml.decode!(~S{<a name="outer'inner'"/>}) == %E{
             name: "a",
             attributes: %{"name" => ~S{outer'inner'}},
             children: []
           }

    assert Xml.decode!(~S{<a name='outer"inner"'/>}) == %E{
             name: "a",
             attributes: %{"name" => ~S{outer"inner"}},
             children: []
           }

    # Escape on encode
    assert Xml.decode!(~S{<a name="outer'inner'"/>}) |> Xml.encode() ==
             ~S{<a name='outer&apos;inner&apos;'/>}

    assert Xml.decode!(~S{<a name='outer"inner"'/>}) |> Xml.encode() ==
             ~S{<a name='outer&quot;inner&quot;'/>}
  end
end
