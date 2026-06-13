------------------------------------------------------------------------------
--  Textrender
--
--  Overview
--  --------
--  Textrender is a minimal TrueType glyph rasterization library designed for
--  grid-based, monospaced text editors.
--
--  The library converts Unicode codepoints into alpha-masked glyph bitmaps
--  stored in a single atlas. It also provides the metrics required to place
--  those glyphs correctly within a fixed grid.
--
--  Design Goals
--  ------------
--  - Deterministic and simple rendering pipeline
--  - Minimal feature set tailored to editor use
--  - No hidden layout or shaping logic
--  - Stable and predictable metrics for grid placement
--
--  Textrender intentionally avoids general-purpose text layout concerns and
--  instead focuses on reliable glyph rendering and placement.
--
--  Rendering Model
--  ---------------
--  The rendering pipeline is:
--
--     Codepoint → Glyph → Rasterization → Atlas → Placement
--
--  - Glyphs are rasterized on first use and cached in the atlas
--  - The atlas stores 8-bit alpha coverage values
--  - Metrics are returned separately from bitmap data
--  - The caller is responsible for drawing and layout
--
--  Placement is baseline-based:
--
--     Baseline_Y = Cell_Y + Ascent
--     Glyph_X    = Cell_X + Bearing_X
--     Glyph_Y    = Baseline_Y - Bearing_Y
--
--  Scope
--  -----
--  Textrender supports:
--  - TrueType outlines (glyf/loca)
--  - Unicode mapping via cmap
--  - Composite glyphs with transforms
--  - Grayscale anti-aliasing
--
--  Emoji Support
--  -------------
--  Textrender supports monochrome emoji and symbol glyphs when they are
--  provided as standard TrueType outlines (glyf table).
--
--  Textrender does not support:
--    - Color emoji formats (CBDT/CBLC, sbix, COLR/CPAL, SVG)
--    - Emoji sequences (ZWJ)
--    - Variation selectors
--    - Multi-codepoint grapheme clusters
--
--  Textrender does not support:
--  - Kerning or shaping (GSUB/GPOS)
--  - CFF/CFF2 outlines
--  - Hinting bytecode
--  - Subpixel (LCD) rendering
--  - Complex text layout
--
--  Unsupported emoji are rendered via the normal fallback glyph mechanism.
--  These features are intentionally out of scope.
--
--  Usage Model
--  -----------
--  Typical usage:
--
--     Load_Font(...)
--     for each codepoint:
--        Get_Glyph(...)
--        Place_Glyph_In_Cell(...)
--        draw from atlas
--
--  All text decoding (e.g. UTF-8) and layout decisions are handled by the
--  caller.
--
--  Thread Safety
--  -------------
--  Textrender is not thread-safe. All operations assume single-threaded use.
--
------------------------------------------------------------------------------
package Textrender is

   --  Unicode scalar value accepted by Textrender.
   --
   --  Textrender does not decode UTF-8. The caller is responsible for decoding
   --  text into codepoints before calling Get_Glyph.
   subtype Codepoint is Natural range 0 .. 16#10FFFF#;

   --  Result of public Textrender operations.
   type Status_Code is
     (Success,
      Font_Not_Loaded,
      Font_Load_Failed,
      Glyph_Missing,
      Atlas_Full,
      Invalid_Input);

   --  8-bit alpha value.
   --
   --  0 means fully transparent.
   --  255 means fully covered.
   type Alpha is mod 2 ** 8;

   --  Linear row-major alpha buffer.
   --
   --  The buffer length is Atlas_Width * Atlas_Height.
   type Alpha_Buffer is array (Natural range <>) of Alpha;

   --  Glyph atlas placement and baseline-relative metrics.
   type Glyph_Metric is record
      --  Pixel-space rectangle inside the atlas.
      X : Float;
      Y : Float;
      W : Float;
      H : Float;

      --  Normalized atlas coordinates in the range 0.0 .. 1.0.
      U0 : Float;
      V0 : Float;
      U1 : Float;
      V1 : Float;

      --  Horizontal advance in pixels.
      --
      --  In a grid editor, cursor movement should normally use Cell_Width
      --  rather than Advance_X. This value is still exposed for diagnostics
      --  and font-metric inspection.
      Advance_X : Float;

      --  Horizontal offset from the cell origin to the glyph bitmap.
      Bearing_X : Float;

      --  Vertical offset from baseline upward to glyph bitmap top.
      Bearing_Y : Float;
   end record;

   --  Pixel-space placement for drawing a glyph bitmap.
   type Glyph_Placement is record
      X : Float;
      Y : Float;
   end record;

   --  Load a TrueType font and initialize the glyph atlas.
   --
   --  Path must refer to a supported TrueType font file.
   --
   --  Pixel_Size controls rasterization scale.
   --
   --  Cell_Width and Cell_Height define the editor grid. They are caller-owned
   --  layout values and are not derived from the font.
   --
   --  Atlas_Width and Atlas_Height define the internal alpha atlas dimensions.
   --
   --  Loading a font resets previous font state, atlas contents, and glyph cache.
   function Load_Font
     (Path         : String;
      Pixel_Size   : Positive;
      Cell_Width   : Positive;
      Cell_Height  : Positive;
      Atlas_Width  : Positive;
      Atlas_Height : Positive) return Status_Code;

   --  Reset all internal state.
   --
   --  This unloads the font, clears the atlas, clears the glyph cache, and
   --  restores default metric values.
   procedure Reset;

   --  Font ascent in pixels for the currently loaded font.
   --
   --  The value is measured upward from the baseline.
   function Ascent return Float;

   --  Font descent in pixels for the currently loaded font.
   --
   --  The value is usually negative for TrueType fonts.
   function Descent return Float;

   --  Recommended line height in pixels for the currently loaded font.
   function Line_Height return Float;

   --  Fixed editor grid cell width in pixels.
   function Cell_Width return Positive;

   --  Fixed editor grid cell height in pixels.
   function Cell_Height return Positive;

   --  Return glyph metrics and atlas coordinates for codepoint C.
   --
   --  On first use, the glyph is rasterized into the atlas and cached.
   --  Later calls for the same codepoint return the cached metric.
   --
   --  If C is missing, Textrender uses a fallback glyph and returns
   --  Glyph_Missing. The returned metric is still valid if a fallback glyph
   --  could be found.
   --
   --  Empty glyphs, such as space, return Success with W = 0.0 and H = 0.0.
   --
   --  The caller draws the atlas rectangle using X/Y/W/H or U0/V0/U1/V1,
   --  then places it using Bearing_X and Bearing_Y.
   function Get_Glyph
     (C : Codepoint;
      M : out Glyph_Metric) return Status_Code;

   --  Compute glyph bitmap placement for a grid cell.
   --
   --  Cell_X and Cell_Y are the top-left corner of the editor cell.
   --
   --  The returned X/Y position is the top-left position where the glyph bitmap
   --  should be drawn.
   function Place_Glyph_In_Cell
     (M      : Glyph_Metric;
      Cell_X : Float;
      Cell_Y : Float) return Glyph_Placement;

   --  Atlas width in pixels.
   function Atlas_Width return Positive;

   --  Atlas height in pixels.
   function Atlas_Height return Positive;

   --  Read-only access to the atlas alpha buffer.
   --
   --  The buffer is row-major:
   --
   --     Index = Y * Atlas_Width + X
   --
   --  The returned access value is invalidated by Load_Font and Reset.
   function Atlas_Pixels return access constant Alpha_Buffer;

      --  Return True if Get_Glyph has modified the atlas since the last clear.
   function Atlas_Dirty return Boolean;

   --  Mark the current atlas contents as synchronized with the renderer/GPU.
   procedure Clear_Atlas_Dirty;

   --  Return True if the currently loaded font directly maps codepoint C.
   --
   --  This does not use fallback glyphs and does not rasterize the glyph.
   function Has_Glyph (C : Codepoint) return Boolean;

private

   Max_Composite_Depth : constant Natural := 4;

end Textrender;