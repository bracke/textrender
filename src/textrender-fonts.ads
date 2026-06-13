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

   function Has_Glyph
     (F : Font;
      C : Codepoint) return Boolean;

   function Num_Glyphs (F : Font) return Natural;

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

   type Font_Buffer is array (Positive range <>) of Natural;
   type Font_Buffer_Access is access all Font_Buffer;

   type Table_Info is record
      Found  : Boolean := False;
      Offset : Natural := 0;
      Length : Natural := 0;
   end record;

   type Font is record
      Is_Loaded : Boolean := False;

      Data : Font_Buffer_Access := null;

      Head_Table : Table_Info;
      Hhea_Table : Table_Info;
      Maxp_Table : Table_Info;
      Hmtx_Table : Table_Info;
      Cmap_Table : Table_Info;
      Loca_Table : Table_Info;
      Glyf_Table : Table_Info;

      Units_Per_Em_V        : Positive := 1;
      Index_To_Loc_Format_V : Integer := 0;
      Number_Of_HMetrics_V  : Natural := 0;
      Num_Glyphs_V          : Natural := 0;

      Ascent_V   : Integer := 0;
      Descent_V  : Integer := 0;
      Line_Gap_V : Integer := 0;
   end record;

end Textrender.Fonts;