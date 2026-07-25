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
--     R : Renderer;
--     Load_Font (R, ...);
--     for each codepoint:
--        Get_Glyph (R, ...);
--        Place_Glyph_In_Cell (R, ...);
--        draw from atlas
--
--  All text decoding (e.g. UTF-8) and layout decisions are handled by the
--  caller.
--
--  A Renderer holds a primary font face plus an optional ordered chain of
--  fallback fonts (see Add_Fallback_Font), all sharing one atlas. Per-glyph
--  fallback picks, per codepoint, the first font in the chain that has it.
--  Hold multiple Renderer values to mix regular, bold, italic, etc.
--
--  Thread Safety
--  -------------
--  Textrender is not thread-safe. A single Renderer must not be touched from
--  multiple threads concurrently.
--
------------------------------------------------------------------------------
private with Ada.Finalization;

package Textrender is

   --  Unicode scalar value accepted by Textrender.
   --
   --  Textrender does not decode UTF-8. The caller is responsible for decoding
   --  text into codepoints before calling Get_Glyph.
   subtype Codepoint is Natural range 0 .. 16#10FFFF#;

   --  Result of public Textrender operations.
   --
   --  Rasterize_Failed indicates that the glyph was found in the font and the
   --  atlas had space, but the rasterizer rejected the outline (for example, a
   --  malformed composite glyph). The returned metric is degenerate (W = H = 0)
   --  so callers can treat the glyph as non-drawable and fall back as needed.
   type Status_Code is
     (Success,
      Font_Not_Loaded,
      Font_Load_Failed,
      Glyph_Missing,
      Atlas_Full,
      Rasterize_Failed,
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
      --  Pixel-space rectangle inside the atlas. Always integer-valued.
      X : Natural;
      Y : Natural;
      W : Natural;
      H : Natural;

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

   --  Selects how the loaded font is rendered.
   --
   --  Italic is implemented as a synthetic oblique — the glyph contours are
   --  skewed horizontally by ~12 degrees. It does not load a separate italic
   --  font file, so letterforms keep their upright design but lean to the
   --  right. For better-looking italics, load a real italic font face in a
   --  separate Renderer with Style => Regular.
   type Font_Style is (Regular, Italic);

   --  A Renderer owns a primary font face, an optional fallback font chain,
   --  its glyph atlas, and its glyph cache.
   --
   --  A default-initialized Renderer is empty. Call Load_Font to populate it.
   --  State is released automatically when the Renderer goes out of scope.
   type Renderer is tagged limited private;

   --  Load a TrueType font and initialize the glyph atlas for R.
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
   --  Loading a font resets previous font state, atlas contents, and glyph
   --  cache held by R. It also clears any fallback fonts previously appended
   --  with Add_Fallback_Font.
   function Load_Font
     (R            : in out Renderer;
      Path         : String;
      Pixel_Size   : Positive;
      Cell_Width   : Positive;
      Cell_Height  : Positive;
      Atlas_Width  : Positive;
      Atlas_Height : Positive) return Status_Code;

   --  Append a fallback font to R's ordered font chain.
   --
   --  A primary font must already be loaded with Load_Font; otherwise this
   --  returns Font_Not_Loaded. The fallback font is loaded from Path and
   --  appended after any previously added fallbacks. It shares R's single
   --  atlas, cache, pixel size, and grid — no new atlas is allocated.
   --
   --  Get_Glyph consults the chain in order (primary first, then fallbacks in
   --  the order added) and rasterizes a codepoint from the first font that
   --  directly maps it. This lets a single Renderer render, into one atlas, a
   --  monospace primary plus symbol/CJK fallbacks without the whole frame ever
   --  flipping to a proportional face.
   --
   --  Returns Font_Load_Failed if Path cannot be loaded as a TrueType font.
   function Add_Fallback_Font
     (R    : in out Renderer;
      Path : String) return Status_Code;

   --  Reset R's internal state.
   --
   --  This unloads the font, clears the atlas, clears the glyph cache, and
   --  restores default metric values.
   procedure Reset (R : in out Renderer);

   --  Font ascent in pixels for the font currently loaded in R.
   --
   --  The value is measured upward from the baseline.
   function Ascent (R : Renderer) return Float;

   --  Font descent in pixels for the font currently loaded in R.
   --
   --  The value is usually negative for TrueType fonts.
   function Descent (R : Renderer) return Float;

   --  Recommended line height in pixels for the font currently loaded in R.
   function Line_Height (R : Renderer) return Float;

   --  Fixed editor grid cell width in pixels.
   function Cell_Width (R : Renderer) return Positive;

   --  Fixed editor grid cell height in pixels.
   function Cell_Height (R : Renderer) return Positive;

   --  Return glyph metrics and atlas coordinates for codepoint C.
   --
   --  On first use, the glyph is rasterized into R's atlas and cached.
   --  Later calls for the same codepoint return the cached metric.
   --
   --  If C is missing, Textrender uses a fallback glyph and returns
   --  Glyph_Missing. The returned metric is still valid if a fallback glyph
   --  could be found.
   --
   --  Empty glyphs, such as space, return Success with W = H = 0.
   --
   --  The caller draws the atlas rectangle using X/Y/W/H or U0/V0/U1/V1,
   --  then places it using Bearing_X and Bearing_Y.
   function Get_Glyph
     (R     : in out Renderer;
      C     : Codepoint;
      M     : out Glyph_Metric;
      Style : Font_Style := Regular) return Status_Code;

   --  Return glyph metrics and atlas coordinates for a concrete font glyph
   --  index in the primary loaded font.
   --
   --  This is intended for callers that already performed shaping and received
   --  glyph IDs from the same primary font face. It does not perform Unicode
   --  cmap lookup and it does not consult fallback fonts.
   function Get_Glyph_By_Index
     (R           : in out Renderer;
      Glyph_Index : Natural;
      M           : out Glyph_Metric;
      Font_Index  : Natural := 0;
      Style       : Font_Style := Regular) return Status_Code;

   --  Compute glyph bitmap placement for a grid cell.
   --
   --  Cell_X and Cell_Y are the top-left corner of the editor cell.
   --
   --  The returned X/Y position is the top-left position where the glyph bitmap
   --  should be drawn.
   function Place_Glyph_In_Cell
     (R      : Renderer;
      M      : Glyph_Metric;
      Cell_X : Float;
      Cell_Y : Float) return Glyph_Placement;

   --  Atlas width in pixels.
   function Atlas_Width (R : Renderer) return Positive;

   --  Atlas height in pixels.
   function Atlas_Height (R : Renderer) return Positive;

   --  Read-only access to R's atlas alpha buffer.
   --
   --  The buffer is row-major:
   --
   --     Index = Y * Atlas_Width + X
   --
   --  The returned access value is invalidated by Load_Font and Reset.
   function Atlas_Pixels (R : Renderer) return access constant Alpha_Buffer;

   --  Return True if Get_Glyph has modified R's atlas since the last clear.
   function Atlas_Dirty (R : Renderer) return Boolean;

   --  Mark R's atlas contents as synchronized with the renderer/GPU.
   procedure Clear_Atlas_Dirty (R : in out Renderer);

   --  Return True if R's font directly maps codepoint C.
   --
   --  This does not use fallback glyphs and does not rasterize the glyph.
   function Has_Glyph (R : Renderer; C : Codepoint) return Boolean;

   --  Rasterize and cache every codepoint in the inclusive range First .. Last.
   --
   --  This is intended for warming common ranges (for example ASCII) at startup
   --  so the first frame does not pay per-glyph rasterization cost.
   --
   --  Returns Font_Not_Loaded if no font is currently loaded in R.
   --  Returns Atlas_Full if the atlas filled before the whole range was cached.
   --  Otherwise returns Success, even when individual codepoints used the
   --  fallback glyph.
   function Preload
     (R     : in out Renderer;
      First : Codepoint;
      Last  : Codepoint) return Status_Code;

private

   Max_Composite_Depth : constant Natural := 4;

   type Renderer_State;
   type Renderer_State_Access is access Renderer_State;

   type Renderer is
     new Ada.Finalization.Limited_Controlled with record
        State : Renderer_State_Access := null;
     end record;

   overriding procedure Initialize (R : in out Renderer);
   overriding procedure Finalize   (R : in out Renderer);

end Textrender;
