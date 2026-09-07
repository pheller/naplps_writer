defmodule NaplpsText do
  # Copyright 2026, Ralph Richard Cook
  #
  # This file is part of Prodigy Reloaded.
  #
  # Prodigy Reloaded is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General
  # Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
  # option) any later version.
  #
  # Prodigy Reloaded is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
  # the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
  # GNU Affero General Public License for more details.
  #
  # You should have received a copy of the GNU Affero General Public License along with Prodigy Reloaded. If not,
  # see <https://www.gnu.org/licenses/>.

  @moduledoc """
  Text measurement and line breaking for the NAPLPS proportional font.

  The NAPLPS text font is proportionally spaced, so a character count says
  little about how wide a string actually draws. Anything that has to fit text
  into a known area - centering a headline, right-aligning a byline, deciding
  where a line of body copy ends - needs real advance widths.

  `text_width/2` measures; `wrap/4` breaks a paragraph into lines that fit.

  ## Where the numbers come from

  The advance of a character is a function of its *width class* and the text
  size:

      advance = char_width * disp[clamp(char_width, 6, 11) - 6][width_class(c)]
                           / clamp(char_width, 6, 11)

  The two tables are transcribed from the FoxCouncil NAPLPS renderer
  (`NAPLPS/Drawing/DrawableAsciiChar.cs`), which is a deliberate match to the
  output of period renderers. Its own notes say the strict reading of
  ANSI X3.110 produces visibly different spacing, so treat these as "what the
  real terminals did" rather than "what the standard says".

  Widths come out in the same units as `char_width`, which for Prodigy work is
  GCU units - the numerators of the `n/256` coordinates used elsewhere in this
  library.
  """

  # Width class per ASCII character, 0x20..0x7E.
  @ascii_width_class {
    # 0x20-0x2F   space ! " # $ % & ' ( ) * + , - . /
    9,
    0,
    4,
    6,
    9,
    9,
    9,
    0,
    1,
    1,
    9,
    9,
    3,
    5,
    0,
    9,
    # 0x30-0x3F   0 1 2 3 4 5 6 7 8 9 : ; < = > ?
    5,
    1,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    0,
    3,
    5,
    8,
    5,
    8,
    # 0x40-0x4F   @ A B C D E F G H I J K L M N O
    9,
    5,
    5,
    5,
    5,
    5,
    5,
    8,
    5,
    2,
    5,
    5,
    5,
    9,
    5,
    9,
    # 0x50-0x5F   P Q R S T U V W X Y Z [ \\ ] ^ _
    5,
    6,
    5,
    5,
    9,
    5,
    9,
    9,
    9,
    9,
    9,
    4,
    9,
    4,
    2,
    9,
    # 0x60-0x6F   ` a b c d e f g h i j k l m n o
    1,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    5,
    0,
    4,
    5,
    0,
    9,
    5,
    5,
    # 0x70-0x7E   p q r s t u v w x y z { | } ~
    5,
    5,
    5,
    5,
    2,
    5,
    9,
    9,
    9,
    5,
    5,
    5,
    0,
    5,
    9
  }

  # Displacement by (text size row, width class). Rows are char widths 6..11.
  @displacement {
    {2, 3, 4, 3, 4, 5, 6, 4, 5, 6},
    {3, 4, 5, 4, 5, 6, 7, 5, 6, 7},
    {2, 3, 4, 4, 5, 6, 7, 6, 7, 8},
    {3, 4, 5, 5, 6, 7, 8, 7, 8, 9},
    {4, 5, 6, 6, 7, 8, 9, 8, 9, 10},
    {3, 4, 6, 6, 7, 8, 10, 8, 10, 11}
  }

  # Anything outside printable ASCII falls back to the widest class.
  @fallback_class 9

  @doc """
  Advance width of one character at the given character-field width.

      iex> NaplpsText.char_advance(6, ?W) > NaplpsText.char_advance(6, ?i)
      true
  """
  @spec char_advance(number(), char()) :: float()
  def char_advance(char_width, char) when is_number(char_width) and is_integer(char) do
    n = char_width |> trunc() |> max(6) |> min(11)
    disp = @displacement |> elem(n - 6) |> elem(width_class(char))
    char_width * disp / n
  end

  @doc """
  Width of a string, in the same units as `char_width`.

      iex> NaplpsText.text_width(6, "") == 0
      true
  """
  @spec text_width(number(), String.t()) :: float()
  def text_width(char_width, text) when is_binary(text) do
    text
    |> to_charlist()
    |> Enum.reduce(0.0, fn c, acc -> acc + char_advance(char_width, c) end)
  end

  @doc "Width class (0-9) of a character; the widest class for anything unprintable."
  @spec width_class(char()) :: 0..9
  def width_class(char) when char >= 0x20 and char <= 0x7E,
    do: elem(@ascii_width_class, char - 0x20)

  def width_class(_char), do: @fallback_class

  # --- Hyphenation ----------------------------------------------------------

  # Typographic minimums: never strand fewer than this many letters on either
  # side of the break. Two before and three after is the usual English setting.
  @min_prefix 2
  @min_suffix 3
  @min_word 6

  @vowels ~c"aeiouy"

  # Consonant pairs that spell one sound. A break never falls between them; it
  # goes after the pair instead, so "Washington" gives "Wash-ington" rather
  # than "Was-hington".
  @digraphs ~w(sh ch th ph wh gh ck ng qu)

  # Prefixes that take a break immediately after them, longest first so that
  # "under" wins over "un".
  @prefixes ~w(inter under over trans super semi anti auto multi
               dis pre non mis sub out per pro con com
               un re in im ex de en em)

  # Suffixes that take a break immediately before them, longest first.
  # Only suffixes of 3+ characters survive the @min_suffix filter, so the short
  # ones here are documentation of intent rather than live rules. "ent"/"ant"
  # are deliberately absent: they fire inside "development" and "important",
  # where -ment and -ance already give the correct break.
  @suffixes ~w(ationally ability tional ations ction ssion ution ition ation
               ment ness able ible less ical ance ence ings tion sion
               ing ers est ful ily ies ous ive ial ual
               ly ed er es al ic)

  @doc """
  Candidate hyphenation offsets for a word, as character positions where a
  hyphen may be inserted.

  Rule-based rather than dictionary-based: this is a small library and a
  pattern dictionary would dwarf it. The rules are conservative and prefer
  making no suggestion over making a wrong one - a missed opportunity only
  costs raggedness, while a bad break is visible in the copy.

  Never suggests anything for a word that is short, contains a digit, is all
  capitals (an acronym), or already contains a hyphen - a word with a hyphen
  should break at the hyphen it already has.

      iex> NaplpsText.hyphenation_points("running") != []
      true
      iex> NaplpsText.hyphenation_points("cat")
      []
  """
  @spec hyphenation_points(String.t()) :: [pos_integer()]
  def hyphenation_points(word) when is_binary(word) do
    chars = to_charlist(word)
    len = length(chars)

    cond do
      len < @min_word -> []
      Enum.any?(chars, &(&1 in ?0..?9)) -> []
      String.contains?(word, "-") -> []
      word == String.upcase(word) -> []
      true -> chars |> candidates(len) |> Enum.uniq() |> Enum.sort()
    end
  end

  defp candidates(chars, len) do
    lower = Enum.map(chars, &lower/1)

    arr = List.to_tuple(lower)

    (prefix_points(lower) ++ suffix_points(lower, len) ++ cluster_points(lower, len))
    |> Enum.filter(&(&1 >= @min_prefix and len - &1 >= @min_suffix))
    |> Enum.reject(&ends_doubled?(arr, &1))
  end

  defp prefix_points(lower) do
    word = List.to_string(lower)

    @prefixes
    |> Enum.filter(&String.starts_with?(word, &1))
    |> Enum.map(&String.length/1)
  end

  defp suffix_points(lower, len) do
    word = List.to_string(lower)

    @suffixes
    |> Enum.filter(&String.ends_with?(word, &1))
    |> Enum.map(&(len - String.length(&1)))
  end

  # Structural breaks inside the word. Two rules carry most of English:
  # split a doubled consonant (run-ning), and split the middle of a
  # vowel-consonant-consonant-vowel run (car-pet). Also "-le" endings
  # (ta-ble), which take the consonant before the l.
  defp cluster_points(lower, len) do
    idx = Enum.with_index(lower)
    arr = List.to_tuple(lower)

    doubled =
      for {c, i} <- idx,
          i > 0,
          i < len - 1,
          consonant?(c),
          elem(arr, i - 1) == c,
          do: i

    vccv =
      for i <- 1..max(len - 3, 1),
          i + 2 < len,
          vowel?(elem(arr, i - 1)),
          consonant?(elem(arr, i)),
          consonant?(elem(arr, i + 1)),
          vowel?(elem(arr, i + 2)) do
        if digraph?(elem(arr, i), elem(arr, i + 1)), do: i + 2, else: i + 1
      end

    consonant_le =
      if len >= 4 and Enum.take(lower, -2) == ~c"le" and consonant?(elem(arr, len - 3)),
        do: [len - 3],
        else: []

    doubled ++ vccv ++ consonant_le
  end

  defp lower(c) when c >= ?A and c <= ?Z, do: c + 32
  defp lower(c), do: c

  # A break must not leave a doubled consonant at the end of the fragment: the
  # correct break for "running" is between the n's, and that candidate is
  # already on the list, so "runn-ing" is only ever the worse of the two.
  defp ends_doubled?(arr, at) when at >= 2 do
    a = elem(arr, at - 1)
    a == elem(arr, at - 2) and consonant?(a)
  end

  defp ends_doubled?(_arr, _at), do: false

  defp digraph?(a, b), do: <<lower(a), lower(b)>> in @digraphs

  defp vowel?(c), do: lower(c) in @vowels
  defp consonant?(c), do: lower(c) in ?a..?z and lower(c) not in @vowels

  # --- Line breaking --------------------------------------------------------

  @doc """
  Break `text` into lines that each fit within `max_width`.

  Greedy: fill a line until the next word will not fit, then try to hyphenate
  that word so part of it still fits, and otherwise start a new line. A word
  too long for an empty line is split at the last character that fits, with a
  hyphen, so nothing ever silently overflows.

  Options:

    * `:hyphenate` - default `true`. With `false`, words move whole.
    * `:hyphen` - the character to append at a break, default `?-`.
    * `:break_capitalized` - default `false`. Capitalized words are left whole,
      because in news copy they are nearly always proper nouns and a broken
      name ("Miche-lle") reads worse than a short line.

  Widths are measured with `text_width/2`, so `max_width` is in the same units
  as `char_width`.

      iex> NaplpsText.wrap("hello world", 6, 1000)
      ["hello world"]
  """
  @spec wrap(String.t(), number(), number(), keyword()) :: [String.t()]
  def wrap(text, char_width, max_width, opts \\ []) when is_binary(text) do
    hyphenate? = Keyword.get(opts, :hyphenate, true)
    hyphen = Keyword.get(opts, :hyphen, ?-)
    caps? = Keyword.get(opts, :break_capitalized, false)

    text
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reduce({[], ""}, fn word, {lines, current} ->
      may_break? = hyphenate? and (caps? or not capitalized?(word))
      place(word, current, lines, char_width, max_width, may_break?, hyphen)
    end)
    |> then(fn {lines, current} ->
      Enum.reverse(if current == "", do: lines, else: [current | lines])
    end)
  end

  defp place(word, current, lines, cw, max, hyphenate?, hyphen) do
    candidate = if current == "", do: word, else: current <> " " <> word

    if text_width(cw, candidate) <= max do
      {lines, candidate}
    else
      split = if hyphenate?, do: split_word(word, current, cw, max, hyphen), else: nil

      case {split, current} do
        # Part of the word fits after what is already on the line.
        {{head, tail}, _} ->
          {[head | lines], tail}

        # Nothing fits alongside the current line: close it and retry the word
        # on a fresh one.
        {nil, current} when current != "" ->
          place(word, "", [current | lines], cw, max, hyphenate?, hyphen)

        # Alone on an empty line and still too wide: hard-split so it cannot
        # overflow the field.
        {nil, _} ->
          {head, tail} = hard_split(word, cw, max, hyphen)
          {[head | lines], tail}
      end
    end
  end

  defp capitalized?(<<c, rest::binary>>) when c >= ?A and c <= ?Z,
    do: rest =~ ~r/[a-z]/

  defp capitalized?(_word), do: false

  # Longest hyphenation point whose first half still fits on the current line.
  defp split_word(word, current, cw, max, hyphen) do
    prefix = if current == "", do: "", else: current <> " "

    word
    |> hyphenation_points()
    |> Enum.reverse()
    |> Enum.find_value(fn at ->
      head = String.slice(word, 0, at) <> <<hyphen>>
      line = prefix <> head

      if text_width(cw, line) <= max do
        {line, String.slice(word, at, String.length(word) - at)}
      end
    end)
  end

  defp hard_split(word, cw, max, hyphen) do
    len = String.length(word)

    take =
      Enum.find((len - 1)..1//-1, 1, fn n ->
        text_width(cw, String.slice(word, 0, n) <> <<hyphen>>) <= max
      end)

    {String.slice(word, 0, take) <> <<hyphen>>, String.slice(word, take, len - take)}
  end
end
