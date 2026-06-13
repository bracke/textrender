with Textrender.Fonts; use Textrender.Fonts;
with Textrender.Atlases;
with Textrender.Rasterizer;
with Ada.Containers.Ordered_Maps;

package body Textrender is

   Atlas_Dirty_V : Boolean := False;
   Font  : Textrender.Fonts.Font;
   Atlas : Textrender.Atlases.Atlas;

   type Cached_Glyph is record
      Status : Status_Code := Success;
      Metric : Glyph_Metric;
   end record;

   package Glyph_Caches is new Ada.Containers.Ordered_Maps
     (Key_Type     => Codepoint,
      Element_Type => Cached_Glyph);

   Glyph_Cache : Glyph_Caches.Map;

   Pixel_Size_V : Positive := 1;
   Cell_Width_V : Positive := 1;
   Cell_Height_V : Positive := 1;

   Glyph_Padding : constant Natural := 1;

   use type Textrender.Fonts.Glyph_Lookup_Result;

   -----------------------------
   -- Reset
   -----------------------------

   procedure Reset is
   begin
      Textrender.Fonts.Reset (Font);
      Textrender.Atlases.Reset (Atlas);

      Glyph_Cache.Clear;

      Pixel_Size_V := 1;
      Cell_Width_V := 1;
      Cell_Height_V := 1;

      Atlas_Dirty_V := False;
   end Reset;

   -----------------------------
   -- Load_Font
   -----------------------------

   function Load_Font
     (Path         : String;
      Pixel_Size   : Positive;
      Cell_Width   : Positive;
      Cell_Height  : Positive;
      Atlas_Width  : Positive;
      Atlas_Height : Positive) return Status_Code
   is
      Result : Textrender.Fonts.Load_Result;
   begin
      Reset;

      Result := Textrender.Fonts.Load (Font, Path);

      if Result /= Textrender.Fonts.Loaded then
         return Font_Load_Failed;
      end if;

      Pixel_Size_V := Pixel_Size;
      Cell_Width_V := Cell_Width;
      Cell_Height_V := Cell_Height;

      Textrender.Atlases.Init
        (Atlas,
         Width  => Atlas_Width,
         Height => Atlas_Height);

      Atlas_Dirty_V := True;

      return Success;
   end Load_Font;

   -----------------------------
   -- Metrics
   -----------------------------

   function Ascent return Float is
   begin
      return
        Float (Textrender.Fonts.Ascent (Font))
        * Float (Pixel_Size_V)
        / Float (Textrender.Fonts.Units_Per_Em (Font));
   end Ascent;

   function Descent return Float is
   begin
      return
        Float (Textrender.Fonts.Descent (Font))
        * Float (Pixel_Size_V)
        / Float (Textrender.Fonts.Units_Per_Em (Font));
   end Descent;

   function Line_Height return Float is
   begin
      return
        Float
          (Textrender.Fonts.Ascent (Font)
           - Textrender.Fonts.Descent (Font)
           + Textrender.Fonts.Line_Gap (Font))
        * Float (Pixel_Size_V)
        / Float (Textrender.Fonts.Units_Per_Em (Font));
   end Line_Height;

   function Cell_Width return Positive is
   begin
      return Cell_Width_V;
   end Cell_Width;

   function Cell_Height return Positive is
   begin
      return Cell_Height_V;
   end Cell_Height;

   function Has_Glyph
     (C : Codepoint) return Boolean
   is
   begin
      return Textrender.Fonts.Has_Glyph (Font, C);
   end Has_Glyph;

   -----------------------------
   -- Get_Glyph
   -----------------------------

   function Get_Glyph
     (C : Codepoint;
      M : out Glyph_Metric) return Status_Code
   is
      G : Textrender.Fonts.Glyph_Info;

      Lookup_Result : Textrender.Fonts.Glyph_Lookup_Result;

      Pack_X  : Natural;
      Pack_Y  : Natural;
      Atlas_X : Natural;
      Atlas_Y : Natural;

      Scale : constant Float :=
        Float (Pixel_Size_V)
        / Float (Textrender.Fonts.Units_Per_Em (Font));

      Glyph_W : Positive;
      Glyph_H : Positive;

      Raw_W : Float;
      Raw_H : Float;

      Return_Status : Status_Code;
   begin
      if not Textrender.Fonts.Loaded (Font) then
         return Font_Not_Loaded;
      end if;

      if Glyph_Cache.Contains (C) then
         declare
            Cached : constant Cached_Glyph := Glyph_Cache.Element (C);
         begin
            M := Cached.Metric;
            return Cached.Status;
         end;
      end if;

      Lookup_Result :=
        Textrender.Fonts.Lookup_Glyph (Font, C, G);

      if Lookup_Result = Textrender.Fonts.Glyph_Not_Found then
         return Glyph_Missing;
      end if;

      --  Empty glyph (space etc.)
      if G.Is_Empty then
         M.X := 0.0;
         M.Y := 0.0;
         M.W := 0.0;
         M.H := 0.0;

         M.U0 := 0.0;
         M.V0 := 0.0;
         M.U1 := 0.0;
         M.V1 := 0.0;

         M.Advance_X :=
           Float (G.Advance_X) * Scale;

         M.Bearing_X :=
           Float (G.Left_Side_Bearing) * Scale;

         M.Bearing_Y := 0.0;

         Return_Status :=
           (if Lookup_Result = Textrender.Fonts.Glyph_Used_Fallback
            then Glyph_Missing
            else Success);

         Glyph_Cache.Insert
           (Key      => C,
            New_Item =>
              (Status => Return_Status,
               Metric => M));

         return Return_Status;
      end if;

      Raw_W := Float (G.Bounds.X_Max - G.Bounds.X_Min) * Scale;
      Raw_H := Float (G.Bounds.Y_Max - G.Bounds.Y_Min) * Scale;

      Glyph_W :=
        (if Raw_W <= 0.0 then 1
         else Positive (Integer (Raw_W + 0.999)));

      Glyph_H :=
        (if Raw_H <= 0.0 then 1
         else Positive (Integer (Raw_H + 0.999)));

      if not Textrender.Atlases.Allocate_Rect
        (Atlas,
         W => Glyph_W + Glyph_Padding * 2,
         H => Glyph_H + Glyph_Padding * 2,
         X => Pack_X,
         Y => Pack_Y)
      then
         return Atlas_Full;
      end if;

      Atlas_X := Pack_X + Glyph_Padding;
      Atlas_Y := Pack_Y + Glyph_Padding;

      if not Textrender.Rasterizer.Rasterize_Glyph
        (F           => Font,
         A           => Atlas,
         Glyph_Index => G.Glyph_Index,
         Atlas_X     => Atlas_X,
         Atlas_Y     => Atlas_Y,
         Glyph_W     => Glyph_W,
         Glyph_H     => Glyph_H,
         X_Min       => G.Bounds.X_Min,
         Y_Min       => G.Bounds.Y_Min,
         X_Max       => G.Bounds.X_Max,
         Y_Max       => G.Bounds.Y_Max,
         Pixel_Size  => Pixel_Size_V)
      then
         for Y in Atlas_Y .. Atlas_Y + Glyph_H - 1 loop
            for X in Atlas_X .. Atlas_X + Glyph_W - 1 loop
               if X = Atlas_X or else X = Atlas_X + Glyph_W - 1
                 or else Y = Atlas_Y or else Y = Atlas_Y + Glyph_H - 1
               then
                  Textrender.Atlases.Write_Pixel (Atlas, X, Y, 255);
               else
                  Textrender.Atlases.Write_Pixel (Atlas, X, Y, 96);
               end if;
            end loop;
         end loop;
      end if;

      M.X := Float (Atlas_X);
      M.Y := Float (Atlas_Y);
      M.W := Float (Glyph_W);
      M.H := Float (Glyph_H);

      M.U0 := Float (Atlas_X) / Float (Textrender.Atlases.Width (Atlas));
      M.V0 := Float (Atlas_Y) / Float (Textrender.Atlases.Height (Atlas));
      M.U1 := Float (Atlas_X + Glyph_W) / Float (Textrender.Atlases.Width (Atlas));
      M.V1 := Float (Atlas_Y + Glyph_H) / Float (Textrender.Atlases.Height (Atlas));

      M.Advance_X :=
        Float (G.Advance_X) * Scale;

      M.Bearing_X :=
        Float (G.Left_Side_Bearing) * Scale;

      M.Bearing_Y :=
        Float (G.Bounds.Y_Max) * Scale;

      pragma Assert (M.W >= 0.0);
      pragma Assert (M.H >= 0.0);
      pragma Assert (M.Advance_X >= 0.0);
      pragma Assert (M.U0 <= M.U1);
      pragma Assert (M.V0 <= M.V1);

      Return_Status :=
        (if Lookup_Result = Textrender.Fonts.Glyph_Used_Fallback
         then Glyph_Missing
         else Success);

      Glyph_Cache.Insert
        (Key      => C,
         New_Item =>
           (Status => Return_Status,
            Metric => M));

      Atlas_Dirty_V := True;

      return Return_Status;
   end Get_Glyph;

   function Place_Glyph_In_Cell
     (M      : Glyph_Metric;
      Cell_X : Float;
      Cell_Y : Float) return Glyph_Placement
   is
      Baseline_Y : constant Float := Cell_Y + Ascent;
   begin
      return
        (X => Cell_X + M.Bearing_X,
         Y => Baseline_Y - M.Bearing_Y);
   end Place_Glyph_In_Cell;

   -----------------------------
   -- Atlas Access
   -----------------------------

   function Atlas_Width return Positive is
   begin
      return Textrender.Atlases.Width (Atlas);
   end Atlas_Width;

   function Atlas_Height return Positive is
   begin
      return Textrender.Atlases.Height (Atlas);
   end Atlas_Height;

   function Atlas_Pixels return access constant Alpha_Buffer is
   begin
      return Textrender.Atlases.Pixels (Atlas);
   end Atlas_Pixels;

   function Atlas_Dirty return Boolean is
   begin
      return Atlas_Dirty_V;
   end Atlas_Dirty;

   procedure Clear_Atlas_Dirty is
   begin
      Atlas_Dirty_V := False;
   end Clear_Atlas_Dirty;

end Textrender;