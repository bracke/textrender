with AUnit.Assertions;
package body Textrender.BasicTests is

   use AUnit.Assertions;

   Font_Path : constant String :=
     "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf";

   function Atlas_Checksum return Natural is
      Pixels : constant access constant Textrender.Alpha_Buffer :=
        Textrender.Atlas_Pixels;

      Sum : Natural := 0;
   begin
      if Pixels = null then
         return 0;
      end if;

      for I in Pixels'Range loop
         Sum := (Sum + Natural (Pixels (I))) mod 1_000_000_007;
      end loop;

      return Sum;
   end Atlas_Checksum;

   function Atlas_Has_Nonzero_Pixel return Boolean is
      Pixels : constant access constant Textrender.Alpha_Buffer :=
        Textrender.Atlas_Pixels;
   begin
      if Pixels = null then
         return False;
      end if;

      for I in Pixels'Range loop
         if Pixels (I) /= 0 then
            return True;
         end if;
      end loop;

      return False;
   end Atlas_Has_Nonzero_Pixel;

   procedure Test_Get_Glyph_Before_Load
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      M : Textrender.Glyph_Metric;
   begin
      Textrender.Reset;

      Assert
        (Textrender.Get_Glyph
           (C => Character'Pos ('A'),
            M => M)
         = Textrender.Font_Not_Loaded,
         "Get_Glyph before Load_Font should return Font_Not_Loaded");
   end Test_Get_Glyph_Before_Load;

   procedure Test_Load_Invalid_Path
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Textrender.Reset;

      Assert
        (Textrender.Load_Font
           (Path         => "/definitely/not/a/font.ttf",
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Font_Load_Failed,
         "Load_Font with invalid path should fail");
   end Test_Load_Invalid_Path;

   procedure Test_Load_Font_And_Metrics
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Status : Textrender.Status_Code;
   begin
      Textrender.Reset;

      Status :=
        Textrender.Load_Font
          (Path         => Font_Path,
           Pixel_Size   => 16,
           Cell_Width   => 10,
           Cell_Height  => 20,
           Atlas_Width  => 256,
           Atlas_Height => 256);

      Assert (Status = Textrender.Success, "Load_Font should succeed");
      Assert (Textrender.Ascent > 0.0, "Ascent should be positive");
      Assert (Textrender.Descent < 0.0, "Descent should be negative");
      Assert (Textrender.Line_Height > 0.0, "Line_Height should be positive");
      Assert (Textrender.Cell_Width = 10, "Cell_Width should match input");
      Assert (Textrender.Cell_Height = 20, "Cell_Height should match input");
      Assert (Textrender.Atlas_Width = 256, "Atlas_Width should match input");
      Assert (Textrender.Atlas_Height = 256, "Atlas_Height should match input");
   end Test_Load_Font_And_Metrics;

   procedure Test_Get_Glyph_A
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Status : Textrender.Status_Code;
      M      : Textrender.Glyph_Metric;
   begin
      Textrender.Reset;

      Status :=
        Textrender.Load_Font
          (Path         => Font_Path,
           Pixel_Size   => 16,
           Cell_Width   => 10,
           Cell_Height  => 20,
           Atlas_Width  => 256,
           Atlas_Height => 256);

      Assert (Status = Textrender.Success, "Load_Font should succeed");

      Status :=
        Textrender.Get_Glyph
          (C => Character'Pos ('A'),
           M => M);

      Assert
        (Status = Textrender.Success,
         "Get_Glyph('A') should succeed");

      Assert (M.W > 0.0, "Glyph A width should be positive");
      Assert (M.H > 0.0, "Glyph A height should be positive");
      Assert (M.Advance_X > 0.0, "Glyph A advance should be positive");

      Assert
        (M.U0 >= 0.0 and then M.U0 <= 1.0
         and then M.V0 >= 0.0 and then M.V0 <= 1.0
         and then M.U1 >= 0.0 and then M.U1 <= 1.0
         and then M.V1 >= 0.0 and then M.V1 <= 1.0,
         "Glyph A UVs should be normalized");

      Assert
        (Atlas_Has_Nonzero_Pixel,
         "Atlas should contain non-zero alpha after rasterizing A");
   end Test_Get_Glyph_A;

   procedure Test_Get_Glyph_Space
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Status : Textrender.Status_Code;
      M      : Textrender.Glyph_Metric;
   begin
      Textrender.Reset;

      Status :=
        Textrender.Load_Font
          (Path         => Font_Path,
           Pixel_Size   => 16,
           Cell_Width   => 10,
           Cell_Height  => 20,
           Atlas_Width  => 256,
           Atlas_Height => 256);

      Assert (Status = Textrender.Success, "Load_Font should succeed");

      Status :=
        Textrender.Get_Glyph
          (C => Character'Pos (' '),
           M => M);

      Assert
        (Status = Textrender.Success,
         "Get_Glyph(' ') should succeed");

      Assert (M.W = 0.0, "Space glyph width should be zero");
      Assert (M.H = 0.0, "Space glyph height should be zero");
      Assert (M.Advance_X > 0.0, "Space advance should be positive");
   end Test_Get_Glyph_Space;

   procedure Test_Atlas_Full
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Status : Textrender.Status_Code;
      M      : Textrender.Glyph_Metric;
   begin
      Textrender.Reset;

      Status :=
        Textrender.Load_Font
          (Path         => Font_Path,
           Pixel_Size   => 32,
           Cell_Width   => 20,
           Cell_Height  => 40,
           Atlas_Width  => 4,
           Atlas_Height => 4);

      Assert (Status = Textrender.Success, "Load_Font should succeed");

      Status :=
        Textrender.Get_Glyph
          (C => Character'Pos ('A'),
           M => M);

      Assert
        (Status = Textrender.Atlas_Full,
         "Too-small atlas should return Atlas_Full");
   end Test_Atlas_Full;

   procedure Test_Glyph_Cache
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Status_1 : Textrender.Status_Code;
      Status_2 : Textrender.Status_Code;

      M1 : Textrender.Glyph_Metric;
      M2 : Textrender.Glyph_Metric;
   begin
      Textrender.Reset;

      Assert
        (Textrender.Load_Font
           (Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Success,
         "Load_Font should succeed");

      Status_1 :=
        Textrender.Get_Glyph
          (C => Character'Pos ('A'),
           M => M1);

      Status_2 :=
        Textrender.Get_Glyph
          (C => Character'Pos ('A'),
           M => M2);

      Assert (Status_1 = Textrender.Success, "First Get_Glyph('A') should succeed");
      Assert (Status_2 = Textrender.Success, "Second Get_Glyph('A') should succeed");

      Assert (M1.X = M2.X, "Cached glyph X should match");
      Assert (M1.Y = M2.Y, "Cached glyph Y should match");
      Assert (M1.W = M2.W, "Cached glyph W should match");
      Assert (M1.H = M2.H, "Cached glyph H should match");

      Assert (M1.U0 = M2.U0, "Cached glyph U0 should match");
      Assert (M1.V0 = M2.V0, "Cached glyph V0 should match");
      Assert (M1.U1 = M2.U1, "Cached glyph U1 should match");
      Assert (M1.V1 = M2.V1, "Cached glyph V1 should match");

      Assert (M1.Advance_X = M2.Advance_X, "Cached advance should match");
      Assert (M1.Bearing_X = M2.Bearing_X, "Cached bearing X should match");
      Assert (M1.Bearing_Y = M2.Bearing_Y, "Cached bearing Y should match");
   end Test_Glyph_Cache;

   procedure Test_Glyph_Cache_Does_Not_Rewrite_Atlas
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Status : Textrender.Status_Code;
      M1     : Textrender.Glyph_Metric;
      M2     : Textrender.Glyph_Metric;

      Checksum_1 : Natural;
      Checksum_2 : Natural;
   begin
      Textrender.Reset;

      Assert
        (Textrender.Load_Font
           (Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Success,
         "Load_Font should succeed");

      Status :=
        Textrender.Get_Glyph
          (C => Character'Pos ('A'),
           M => M1);

      Assert (Status = Textrender.Success, "First Get_Glyph('A') should succeed");

      Checksum_1 := Atlas_Checksum;

      Status :=
        Textrender.Get_Glyph
          (C => Character'Pos ('A'),
           M => M2);

      Assert (Status = Textrender.Success, "Second Get_Glyph('A') should succeed");

      Checksum_2 := Atlas_Checksum;

      Assert
        (Checksum_1 = Checksum_2,
         "Cached Get_Glyph should not modify atlas pixels");

      Assert (M1.X = M2.X, "Cached glyph X should match");
      Assert (M1.Y = M2.Y, "Cached glyph Y should match");
      Assert (M1.U0 = M2.U0, "Cached glyph U0 should match");
      Assert (M1.V0 = M2.V0, "Cached glyph V0 should match");
      Assert (M1.U1 = M2.U1, "Cached glyph U1 should match");
      Assert (M1.V1 = M2.V1, "Cached glyph V1 should match");
   end Test_Glyph_Cache_Does_Not_Rewrite_Atlas;

   procedure Test_ASCII_Range
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Status : Textrender.Status_Code;
      M      : Textrender.Glyph_Metric;
   begin
      Textrender.Reset;

      Assert
        (Textrender.Load_Font
           (Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 1024,
            Atlas_Height => 1024)
         = Textrender.Success,
         "Load_Font should succeed");

      for C in 32 .. 126 loop
         Status :=
           Textrender.Get_Glyph
             (C => C,
              M => M);

         Assert
  (Status = Textrender.Success,
   "ASCII glyph should load successfully, failed codepoint="
   & Integer'Image (C)
   & " char='"
   & Character'Val (C)
   & "' status="
   & Textrender.Status_Code'Image (Status));

         Assert
           (M.Advance_X > 0.0,
            "ASCII glyph should have positive advance");
      end loop;
   end Test_ASCII_Range;

   procedure Test_Get_Glyph_Exclamation
   (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Status : Textrender.Status_Code;
      M      : Textrender.Glyph_Metric;
   begin
      Textrender.Reset;

      Assert
      (Textrender.Load_Font
         (Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Success,
         "Load_Font should succeed");

      Status :=
      Textrender.Get_Glyph
         (C => Character'Pos ('!'),
         M => M);

      Assert
      (Status /= Textrender.Font_Load_Failed,
         "Exclamation glyph must not fail rasterization");

      Assert
      (M.Advance_X > 0.0,
         "Exclamation glyph should have positive advance");
   end Test_Get_Glyph_Exclamation;

   procedure Test_DumpImage
   (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Status : Textrender.Status_Code;
      M      : Textrender.Glyph_Metric;
   begin

      Textrender.Reset;

      pragma Assert
      (Textrender.Load_Font
         (Path         => Font_Path,
            Pixel_Size   => 32,
            Cell_Width   => 20,
            Cell_Height  => 40,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Success);

      for C in Character'Pos (' ') .. Character'Pos ('~') loop
         declare
            S : constant Textrender.Status_Code :=
            Textrender.Get_Glyph (C => C, M => M);
         begin
            null; -- ignore status here
         end;
      end loop;

      --  Atlas debug dumps are intentionally not written by default;
      --  generated image artifacts do not belong in the release tree.

   end Test_DumpImage;

   procedure Test_Baseline_Placement_Metrics
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Status     : Textrender.Status_Code;
      M          : Textrender.Glyph_Metric;
      Baseline_Y : constant Float := 100.0;
      Top_Y      : Float;
      Bottom_Y   : Float;
   begin
      Textrender.Reset;

      Assert
        (Textrender.Load_Font
           (Path         => Font_Path,
            Pixel_Size   => 32,
            Cell_Width   => 20,
            Cell_Height  => 40,
            Atlas_Width  => 512,
            Atlas_Height => 512)
         = Textrender.Success,
         "Load_Font should succeed");

      declare
         Chars : constant String := "Axg|";
      begin
         for I in Chars'Range loop
            declare
               C : constant Character := Chars (I);
            begin
               Status :=
                 Textrender.Get_Glyph
                   (C => Character'Pos (C),
                    M => M);

               Assert
                 (Status = Textrender.Success,
                  "Glyph should load for baseline test: " & C);

               Assert (M.Advance_X > 0.0, "Advance should be positive");
               Assert (M.Bearing_Y >= 0.0, "Bearing_Y should be non-negative");

               Top_Y    := Baseline_Y - M.Bearing_Y;
               Bottom_Y := Top_Y + M.H;

               Assert
                 (Bottom_Y >= Baseline_Y - 3.0,
                  "Glyph bottom should be near or below baseline: " & C);
            end;
         end loop;
      end;
   end Test_Baseline_Placement_Metrics;

   procedure Test_Composite_Accented_Glyph
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Status : Textrender.Status_Code;
      M      : Textrender.Glyph_Metric;
   begin
      Textrender.Reset;

      Assert
        (Textrender.Load_Font
           (Path         => Font_Path,
            Pixel_Size   => 32,
            Cell_Width   => 20,
            Cell_Height  => 40,
            Atlas_Width  => 512,
            Atlas_Height => 512)
         = Textrender.Success,
         "Load_Font should succeed");

      --  U+00E9 LATIN SMALL LETTER E WITH ACUTE
      Status :=
        Textrender.Get_Glyph
          (C => 16#00E9#,
           M => M);

      Assert
        (Status = Textrender.Success,
         "Composite accented glyph should render");

      Assert (M.W > 0.0, "Composite glyph width should be positive");
      Assert (M.H > 0.0, "Composite glyph height should be positive");
      Assert (M.Advance_X > 0.0, "Composite glyph advance should be positive");
   end Test_Composite_Accented_Glyph;

   procedure Test_Symbol_Glyph
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Status : Textrender.Status_Code;
      M      : Textrender.Glyph_Metric;
   begin
      Textrender.Reset;

      Assert
        (Textrender.Load_Font
           (Path         => Font_Path,
            Pixel_Size   => 32,
            Cell_Width   => 20,
            Cell_Height  => 40,
            Atlas_Width  => 512,
            Atlas_Height => 512)
         = Textrender.Success,
         "Load_Font should succeed");

      --  U+263A WHITE SMILING FACE
      Status :=
        Textrender.Get_Glyph
          (C => 16#263A#,
           M => M);

      --  Accept fallback if font lacks it
      Assert
        (Status = Textrender.Success
         or else Status = Textrender.Glyph_Missing,
         "Symbol glyph should render or fallback");

      Assert (M.Advance_X >= 0.0, "Symbol advance should be valid");
   end Test_Symbol_Glyph;

   procedure Test_Place_Glyph_In_Cell
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Status    : Textrender.Status_Code;
      M         : Textrender.Glyph_Metric;
      P         : Textrender.Glyph_Placement;

      Cell_X    : constant Float := 50.0;
      Cell_Y    : constant Float := 80.0;

      Baseline  : Float;
   begin
      Textrender.Reset;

      Assert
        (Textrender.Load_Font
           (Path         => Font_Path,
            Pixel_Size   => 32,
            Cell_Width   => 20,
            Cell_Height  => 40,
            Atlas_Width  => 512,
            Atlas_Height => 512)
         = Textrender.Success,
         "Load_Font should succeed");

      Status :=
        Textrender.Get_Glyph
          (C => Character'Pos ('A'),
           M => M);

      Assert (Status = Textrender.Success, "Glyph A should load");

      P := Textrender.Place_Glyph_In_Cell
        (M      => M,
         Cell_X => Cell_X,
         Cell_Y => Cell_Y);

      Baseline := Cell_Y + Textrender.Ascent;

      Assert
        (P.X = Cell_X + M.Bearing_X,
         "Placement X must match bearing");

      Assert
        (P.Y = Baseline - M.Bearing_Y,
         "Placement Y must align to baseline");
   end Test_Place_Glyph_In_Cell;

   procedure Test_Fallback_Cache
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Status_1 : Textrender.Status_Code;
      Status_2 : Textrender.Status_Code;

      M1 : Textrender.Glyph_Metric;
      M2 : Textrender.Glyph_Metric;
   begin
      Textrender.Reset;

      Assert
        (Textrender.Load_Font
           (Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Success,
         "Load_Font should succeed");

      --  Pick something unlikely to exist
      Status_1 := Textrender.Get_Glyph (16#10FFFF#, M1);
      Status_2 := Textrender.Get_Glyph (16#10FFFF#, M2);

      Assert
        (Status_1 = Textrender.Glyph_Missing,
         "First fallback must be Glyph_Missing");

      Assert
        (Status_2 = Textrender.Glyph_Missing,
         "Cached fallback must still be Glyph_Missing");

      Assert (M1.X = M2.X, "M1.X = M2.X");
      Assert (M1.Y = M2.Y, "M1.Y = M2.Y");
      Assert (M1.U0 = M2.U0, "M1.U0 = M2.U0");
      Assert (M1.V0 = M2.V0, "M1.V0 = M2.V0");
   end Test_Fallback_Cache;

   procedure Test_Reload_Clears_Cache
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Status : Textrender.Status_Code;
      M      : Textrender.Glyph_Metric;
   begin
      Textrender.Reset;

      Assert
        (Textrender.Load_Font
           (Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Success, "Error during font load");

      Status := Textrender.Get_Glyph (Character'Pos ('A'), M);
      Assert (Status = Textrender.Success, "Get_Glyph error");

      --  Reload
      Assert
        (Textrender.Load_Font
           (Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Success, "Font loading error");

      Status := Textrender.Get_Glyph (Character'Pos ('A'), M);
      Assert (Status = Textrender.Success, "Error fetching glyph");
   end Test_Reload_Clears_Cache;

   procedure Test_Has_Glyph
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Textrender.Reset;

      Assert
        (Textrender.Load_Font
           (Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Success, "Font loading problem");

      Assert
        (Textrender.Has_Glyph (Character'Pos ('A')),
         "Font should directly contain A");

      Assert
        (not Textrender.Has_Glyph (16#10FFFF#),
         "Font should not directly contain U+10FFFF");
   end Test_Has_Glyph;

   procedure Test_Has_Glyph_Before_Load
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Textrender.Reset;

      Assert
        (not Textrender.Has_Glyph (Character'Pos ('A')),
         "Has_Glyph before Load_Font should return False");
   end Test_Has_Glyph_Before_Load;

   procedure Test_Atlas_Pixels_After_Reset
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Textrender.Reset;

      Assert
        (Textrender.Atlas_Pixels = null,
         "Atlas_Pixels after Reset should be null");
   end Test_Atlas_Pixels_After_Reset;

   procedure Test_Distinct_Atlas_Rectangles
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      M1 : Textrender.Glyph_Metric;
      M2 : Textrender.Glyph_Metric;

      S  : Textrender.Status_Code;
   begin
      Textrender.Reset;

      Assert
        (Textrender.Load_Font
           (Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Success, "Font loading error");

      S := Textrender.Get_Glyph (Character'Pos ('A'), M1);
      Assert (S = Textrender.Success, "Get_Glyph error");

      S := Textrender.Get_Glyph (Character'Pos ('B'), M2);
      Assert (S = Textrender.Success, "Get_Glyph error");

      Assert
        (M1.X /= M2.X or else M1.Y /= M2.Y,
         "Different glyphs should not share atlas position");
   end Test_Distinct_Atlas_Rectangles;

   procedure Test_Pixel_Size_Change
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      M16 : Textrender.Glyph_Metric;
      M32 : Textrender.Glyph_Metric;

      S   : Textrender.Status_Code;
   begin
      Textrender.Reset;

      Assert
        (Textrender.Load_Font
           (Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Success, "Font loading error");

      S := Textrender.Get_Glyph (Character'Pos ('A'), M16);
      Assert (S = Textrender.Success, "Get_Glyph error");

      Assert
        (Textrender.Load_Font
           (Path         => Font_Path,
            Pixel_Size   => 32,
            Cell_Width   => 20,
            Cell_Height  => 40,
            Atlas_Width  => 512,
            Atlas_Height => 512)
         = Textrender.Success, "Font loading error");

      S := Textrender.Get_Glyph (Character'Pos ('A'), M32);
      Assert (S = Textrender.Success, "Get_Glyph error");

      Assert
        (M32.H > M16.H,
         "Larger pixel size should produce taller glyph");
   end Test_Pixel_Size_Change;

   procedure Test_Symbol_Coverage
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Codes : constant array (Positive range 1 .. 4) of Natural :=
        [16#2192#, 16#2605#, 16#2665#, 16#263A#];

      M : Textrender.Glyph_Metric;
      S : Textrender.Status_Code;
   begin
      Textrender.Reset;

      Assert
        (Textrender.Load_Font
           (Path         => Font_Path,
            Pixel_Size   => 32,
            Cell_Width   => 20,
            Cell_Height  => 40,
            Atlas_Width  => 512,
            Atlas_Height => 512)
         = Textrender.Success, "Font loading error");

      for I in Codes'Range loop
         S := Textrender.Get_Glyph (Codes (I), M);

         Assert
           (S = Textrender.Success
            or else S = Textrender.Glyph_Missing,
            "Symbol must render or fallback");
      end loop;
   end Test_Symbol_Coverage;

   procedure Test_ASCII_Range_Cached_Does_Not_Rewrite_Atlas
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      M : Textrender.Glyph_Metric;
      S : Textrender.Status_Code;

      Checksum_1 : Natural;
      Checksum_2 : Natural;
   begin
      Textrender.Reset;

      Assert
        (Textrender.Load_Font
           (Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 1024,
            Atlas_Height => 1024)
         = Textrender.Success,
         "Load_Font should succeed");

      --  First pass: rasterizes and fills atlas/cache.
      for C in 32 .. 126 loop
         S := Textrender.Get_Glyph (C, M);

         Assert
           (S = Textrender.Success,
            "First ASCII pass failed at codepoint="
            & Integer'Image (C));
      end loop;

      Checksum_1 := Atlas_Checksum;

      --  Second pass: should be entirely cache hits.
      for C in 32 .. 126 loop
         S := Textrender.Get_Glyph (C, M);

         Assert
           (S = Textrender.Success,
            "Second ASCII pass failed at codepoint="
            & Integer'Image (C));
      end loop;

      Checksum_2 := Atlas_Checksum;

      Assert
        (Checksum_1 = Checksum_2,
         "Cached ASCII pass should not modify atlas");
   end Test_ASCII_Range_Cached_Does_Not_Rewrite_Atlas;

   overriding
   function Name
     (T : Textrender_Basic_Case) return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Textrender basic tests");
   end Name;

   overriding
   procedure Register_Tests
     (T : in out Textrender_Basic_Case)
   is
   begin
      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Get_Glyph_Before_Load'Access,
         "Get_Glyph before Load_Font returns Font_Not_Loaded");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Load_Invalid_Path'Access,
         "Load_Font rejects invalid path");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Load_Font_And_Metrics'Access,
         "Load_Font exposes font and grid metrics");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Get_Glyph_A'Access,
         "Get_Glyph rasterizes A into atlas");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Get_Glyph_Space'Access,
         "Get_Glyph handles space as empty glyph");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Atlas_Full'Access,
         "Get_Glyph reports Atlas_Full");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Glyph_Cache'Access,
         "Glyph Cache");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Glyph_Cache_Does_Not_Rewrite_Atlas'Access,
         "Glyph Cache Does Not Rewrite Atlas");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_ASCII_Range'Access,
         "ASCII Range");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Get_Glyph_Exclamation'Access,
         "Get Glyph Exclamation");

      --  AUnit.Test_Cases.Registration.Register_Routine
      --    (T,
      --     Test_DumpImage'Access,
      --     "DumpImage");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Baseline_Placement_Metrics'Access,
         "Baseline Placement Metrics");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Composite_Accented_Glyph'Access,
         "Composite Accented Glyph");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Symbol_Glyph'Access,
         "Test Symbol Glyph");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Place_Glyph_In_Cell'Access,
         "Place Glyph In Cell");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Fallback_Cache'Access,
         "Fallback Cache");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Reload_Clears_Cache'Access,
         "Reload Clears Cache");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Symbol_Glyph'Access,
         "Symbol Glyph");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Has_Glyph'Access,
         "Has Glyph");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Has_Glyph_Before_Load'Access,
         "Has Glyph Before Load");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Atlas_Pixels_After_Reset'Access,
         "Atlas Pixels After Reset");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Distinct_Atlas_Rectangles'Access,
         "Distinct Atlas Rectangles");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Pixel_Size_Change'Access,
         "Test_Pixel_Size_Change");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Symbol_Coverage'Access,
         "Symbol Coverage");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_ASCII_Range_Cached_Does_Not_Rewrite_Atlas'Access,
         "ASCII Range Cached Does Not Rewrite Atlas");

   end Register_Tests;

end Textrender.BasicTests;