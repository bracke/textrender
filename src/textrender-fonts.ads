with Interfaces;

package Textrender.Fonts is

   subtype Codepoint is Natural range 0 .. 16#10FFFF#;

   type Font is private;

   type Load_Result is
     (Loaded,
      Load_Failed,
      Invalid_Input);

   type Glyph_Lookup_Result is
     (Glyph_Found,
      Glyph_Used_Fallback,
      Glyph_Not_Found);

   type Glyph_Bounds is record
      X_Min : Integer := 0;
      Y_Min : Integer := 0;
      X_Max : Integer := 0;
      Y_Max : Integer := 0;
   end record;

   type Glyph_Info is record
      Glyph_Index       : Natural := 0;
      Bounds            : Glyph_Bounds;
      Advance_X         : Natural := 0;
      Left_Side_Bearing : Integer := 0;
      Is_Empty          : Boolean := True;
      Used_Fallback     : Boolean := False;
   end record;

   procedure Reset (F : in out Font);

   function Load
     (F    : in out Font;
      Path : String) return Load_Result;

   function Loaded (F : Font) return Boolean;

   function Units_Per_Em (F : Font) return Positive;

   function Ascent (F : Font) return Integer;
   function Descent (F : Font) return Integer;
   function Line_Gap (F : Font) return Integer;

   function Lookup_Glyph
     (F : Font;
      C : Codepoint;
      G : out Glyph_Info) return Glyph_Lookup_Result;

   function Lookup_Glyph_By_Index
     (F           : Font;
      Glyph_Index : Natural;
      G           : out Glyph_Info) return Glyph_Lookup_Result;

   function Has_Glyph
     (F : Font;
      C : Codepoint) return Boolean;

   function Num_Glyphs (F : Font) return Natural;

   --  The glyph index this font's character map gives a codepoint, reading no
   --  outline at all.
   --
   --  Lookup_Glyph cannot answer for a colour font: it reads the glyph's bounds
   --  from glyf to fill in the metrics, and a bitmap-only font has no glyf, so
   --  every codepoint came back Glyph_Not_Found however well the character map
   --  mapped it. This is the character map on its own.
   --
   --  @return True when the font maps C, with Glyph_Index set.
   function Glyph_Index_Of
     (F           : Font;
      C           : Codepoint;
      Glyph_Index : out Natural)
      return Boolean;

   --  A colour glyph as the font stores it: an encoded image, and where to put
   --  it. The image is NOT decoded here. Textrender rasterizes outlines; a
   --  colour glyph is a picture the font happens to carry, and decoding pictures
   --  is a different job with a different dependency -- so the bytes and the
   --  metrics come out and the caller supplies the decoder.
   --
   --  Both formats this reads store PNG: CBDT (Google, Noto Color Emoji) and
   --  sbix (Apple Color Emoji). COLR/CPAL is not one of them -- that is layered
   --  outlines rather than an image, and would go through the rasterizer.
   type Colour_Image_Format is (No_Colour_Image, Png_Colour_Image);

   type Colour_Bitmap is record
      Format : Colour_Image_Format := No_Colour_Image;

      --  Where the encoded image sits in the font's own bytes.
      Data_Offset : Natural := 0;
      Data_Length : Natural := 0;

      --  The strike this came from, and the image's size in its pixels. Emoji
      --  strikes are large -- Noto's is 109 ppem with 136x128 bitmaps -- so a
      --  caller drawing at text size is downscaling substantially and should
      --  filter rather than drop pixels.
      Ppem   : Positive := 1;
      Width  : Natural := 0;
      Height : Natural := 0;

      --  Placement in the strike's pixels, as the font gives it: bearing from
      --  the pen position, and how far the pen then moves.
      Bearing_X : Integer := 0;
      Bearing_Y : Integer := 0;
      Advance   : Natural := 0;
   end record;

   --  Does this font carry colour bitmaps at all?
   function Has_Colour_Bitmaps (F : Font) return Boolean;

   --  A single layer of a layered colour glyph: which glyph to draw, and the
   --  colour to draw it in.
   type Colour_Layer is record
      Glyph_Index : Natural := 0;
      Red         : Natural := 0;
      Green       : Natural := 0;
      Blue        : Natural := 0;
      Alpha       : Natural := 255;
   end record;

   --  Does this font build its colour glyphs out of layers rather than pictures?
   --
   --  This is COLR/CPAL, which is what Segoe UI Emoji and Twemoji use: a glyph
   --  is a stack of ordinary outlines, each drawn in a colour from a palette.
   --  Nothing here needs decoding -- the layers are outlines this crate already
   --  rasterizes -- so unlike the picture formats it works with no decoder
   --  installed.
   function Has_Colour_Layers (F : Font) return Boolean;

   --  How many layers this glyph is built from; zero when it has none, which is
   --  normal, since only the emoji in such a font are layered.
   function Colour_Layer_Count
     (F           : Font;
      Glyph_Index : Natural)
      return Natural;

   --  One layer of a layered glyph, counted from zero.
   function Colour_Layer_At
     (F           : Font;
      Glyph_Index : Natural;
      Layer       : Natural)
      return Colour_Layer;

   --  Has this font got no outlines -- only colour bitmaps?
   --
   --  Noto Color Emoji is exactly this: no glyf, no loca, nothing to rasterize.
   --  Such a font loads, and every outline query answers empty rather than
   --  raising, so a caller can hold it in a fallback chain and ask it only for
   --  the codepoints it actually has.
   function Is_Bitmap_Only (F : Font) return Boolean;

   --  The colour glyph for this glyph index, at the strike best matching
   --  Pixel_Size: the smallest strike at least that big, or the largest strike
   --  when every one of them is smaller. Format is No_Colour_Image when this
   --  glyph has no bitmap -- which is normal, since strike coverage is sparse.
   function Colour_Bitmap_For
     (F           : Font;
      Glyph_Index : Natural;
      Pixel_Size  : Positive)
      return Colour_Bitmap;

   function Glyph_Data_Range
     (F           : Font;
      Glyph_Index : Natural;
      First       : out Natural;
      Last        : out Natural) return Boolean;

   function Has_Bytes
     (F      : Font;
      Offset : Natural;
      Count  : Natural) return Boolean;

   function Byte_At
     (F      : Font;
      Offset : Natural) return Natural;

   function U16
     (F      : Font;
      Offset : Natural) return Natural;

   function I16
     (F      : Font;
      Offset : Natural) return Integer;

private

   type Font_Buffer is array (Positive range <>) of Interfaces.Unsigned_8;
   type Font_Buffer_Access is access all Font_Buffer;

   type Table_Info is record
      Found  : Boolean := False;
      Offset : Natural := 0;
      Length : Natural := 0;
   end record;

   type Font is record
      Is_Loaded : Boolean := False;

      Data : Font_Buffer_Access := null;

      --  Where the sfnt offset table starts. Zero for a plain .ttf/.otf; for a .ttc
      --  collection (which begins with a "ttcf" header and a list of face offsets) it is
      --  the offset of the first face. Everything that reads the table directory adds it.
      Sfnt_Base : Natural := 0;

      Head_Table : Table_Info;
      Hhea_Table : Table_Info;
      Maxp_Table : Table_Info;
      Hmtx_Table : Table_Info;
      Cmap_Table : Table_Info;
      Loca_Table : Table_Info;
      Glyf_Table : Table_Info;

      --  Colour bitmap strikes. CBLC indexes them and CBDT holds the images;
      --  sbix carries both in one table. A font may have neither, either, or --
      --  in the case of the emoji fonts -- these and no outlines at all.
      Cblc_Table : Table_Info;
      Cbdt_Table : Table_Info;
      Sbix_Table : Table_Info;
      Colr_Table : Table_Info;
      Cpal_Table : Table_Info;

      Units_Per_Em_V        : Positive := 1;
      Index_To_Loc_Format_V : Integer := 0;
      Number_Of_HMetrics_V  : Natural := 0;
      Num_Glyphs_V          : Natural := 0;

      Ascent_V   : Integer := 0;
      Descent_V  : Integer := 0;
      Line_Gap_V : Integer := 0;
   end record;

end Textrender.Fonts;
