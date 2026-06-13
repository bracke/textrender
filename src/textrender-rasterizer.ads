with Textrender.Atlases;
with Textrender.Fonts;

package Textrender.Rasterizer is

   type Glyph_Transform is record
      XX : Float := 1.0;
      XY : Float := 0.0;
      YX : Float := 0.0;
      YY : Float := 1.0;
      DX : Float := 0.0;
      DY : Float := 0.0;
   end record;

   Identity_Transform : constant Glyph_Transform :=
     (XX => 1.0,
      XY => 0.0,
      YX => 0.0,
      YY => 1.0,
      DX => 0.0,
      DY => 0.0);

   function Rasterize_Glyph
     (F           : Textrender.Fonts.Font;
      A           : in out Textrender.Atlases.Atlas;
      Glyph_Index : Natural;
      Atlas_X     : Natural;
      Atlas_Y     : Natural;
      Glyph_W     : Positive;
      Glyph_H     : Positive;
      X_Min       : Integer;
      Y_Min       : Integer;
      X_Max       : Integer;
      Y_Max       : Integer;
      Pixel_Size  : Positive;
      Transform   : Glyph_Transform := Identity_Transform) return Boolean;

end Textrender.Rasterizer;