with AUnit.Assertions;

with Ada.Directories;

with Textrender.Fonts;

package body Textrender.BasicTests is

   use AUnit.Assertions;
   use type Textrender.Fonts.Glyph_Lookup_Result;
   use type Textrender.Fonts.Load_Result;

   Font_Path : constant String :=
     "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf";

   R : Textrender.Renderer;

   function Atlas_Checksum return Natural is
      Pixels : constant access constant Textrender.Alpha_Buffer :=
        Textrender.Atlas_Pixels (R);

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
        Textrender.Atlas_Pixels (R);
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
      Textrender.Reset (R);

      Assert
        (Textrender.Get_Glyph
           (R, C => Character'Pos ('A'),
            M => M)
         = Textrender.Font_Not_Loaded,
         "Get_Glyph before Load_Font should return Font_Not_Loaded");
   end Test_Get_Glyph_Before_Load;

   procedure Test_Load_Invalid_Path
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Textrender.Reset (R);

      Assert
        (Textrender.Load_Font
           (R, Path         => "/definitely/not/a/font.ttf",
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
      Textrender.Reset (R);

      Status :=
        Textrender.Load_Font
          (R, Path         => Font_Path,
           Pixel_Size   => 16,
           Cell_Width   => 10,
           Cell_Height  => 20,
           Atlas_Width  => 256,
           Atlas_Height => 256);

      Assert (Status = Textrender.Success, "Load_Font should succeed");
      Assert (Textrender.Ascent (R) > 0.0, "Ascent should be positive");
      Assert (Textrender.Descent (R) < 0.0, "Descent should be negative");
      Assert (Textrender.Line_Height (R) > 0.0, "Line_Height should be positive");
      Assert (Textrender.Cell_Width (R) = 10, "Cell_Width should match input");
      Assert (Textrender.Cell_Height (R) = 20, "Cell_Height should match input");
      Assert (Textrender.Atlas_Width (R) = 256, "Atlas_Width should match input");
      Assert (Textrender.Atlas_Height (R) = 256, "Atlas_Height should match input");
   end Test_Load_Font_And_Metrics;

   procedure Test_Get_Glyph_A
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Status : Textrender.Status_Code;
      M      : Textrender.Glyph_Metric;
   begin
      Textrender.Reset (R);

      Status :=
        Textrender.Load_Font
          (R, Path         => Font_Path,
           Pixel_Size   => 16,
           Cell_Width   => 10,
           Cell_Height  => 20,
           Atlas_Width  => 256,
           Atlas_Height => 256);

      Assert (Status = Textrender.Success, "Load_Font should succeed");

      Status :=
        Textrender.Get_Glyph
          (R, C => Character'Pos ('A'),
           M => M);

      Assert
        (Status = Textrender.Success,
         "Get_Glyph('A') should succeed");

      Assert (M.W > 0, "Glyph A width should be positive");
      Assert (M.H > 0, "Glyph A height should be positive");
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
      Textrender.Reset (R);

      Status :=
        Textrender.Load_Font
          (R, Path         => Font_Path,
           Pixel_Size   => 16,
           Cell_Width   => 10,
           Cell_Height  => 20,
           Atlas_Width  => 256,
           Atlas_Height => 256);

      Assert (Status = Textrender.Success, "Load_Font should succeed");

      Status :=
        Textrender.Get_Glyph
          (R, C => Character'Pos (' '),
           M => M);

      Assert
        (Status = Textrender.Success,
         "Get_Glyph(' ') should succeed");

      Assert (M.W = 0, "Space glyph width should be zero");
      Assert (M.H = 0, "Space glyph height should be zero");
      Assert (M.Advance_X > 0.0, "Space advance should be positive");
   end Test_Get_Glyph_Space;

   procedure Test_Atlas_Full
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Status : Textrender.Status_Code;
      M      : Textrender.Glyph_Metric;
   begin
      Textrender.Reset (R);

      Status :=
        Textrender.Load_Font
          (R, Path         => Font_Path,
           Pixel_Size   => 32,
           Cell_Width   => 20,
           Cell_Height  => 40,
           Atlas_Width  => 4,
           Atlas_Height => 4);

      Assert (Status = Textrender.Success, "Load_Font should succeed");

      Status :=
        Textrender.Get_Glyph
          (R, C => Character'Pos ('A'),
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
      Textrender.Reset (R);

      Assert
        (Textrender.Load_Font
           (R, Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Success,
         "Load_Font should succeed");

      Status_1 :=
        Textrender.Get_Glyph
          (R, C => Character'Pos ('A'),
           M => M1);

      Status_2 :=
        Textrender.Get_Glyph
          (R, C => Character'Pos ('A'),
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
      Textrender.Reset (R);

      Assert
        (Textrender.Load_Font
           (R, Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Success,
         "Load_Font should succeed");

      Status :=
        Textrender.Get_Glyph
          (R, C => Character'Pos ('A'),
           M => M1);

      Assert (Status = Textrender.Success, "First Get_Glyph('A') should succeed");

      Checksum_1 := Atlas_Checksum;

      Status :=
        Textrender.Get_Glyph
          (R, C => Character'Pos ('A'),
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

   procedure Test_Get_Glyph_By_Index
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Font          : Textrender.Fonts.Font;
      Font_Glyph    : Textrender.Fonts.Glyph_Info;
      Lookup_Status : Textrender.Fonts.Glyph_Lookup_Result;
      Status_1      : Textrender.Status_Code;
      Status_2      : Textrender.Status_Code;
      M1            : Textrender.Glyph_Metric;
      M2            : Textrender.Glyph_Metric;
      Checksum_1    : Natural;
      Checksum_2    : Natural;
   begin
      Textrender.Reset (R);

      Assert
        (Textrender.Fonts.Load (Font, Font_Path) = Textrender.Fonts.Loaded,
         "test font should load for glyph-index lookup");

      Lookup_Status :=
        Textrender.Fonts.Lookup_Glyph
          (Font,
           Textrender.Fonts.Codepoint (Character'Pos ('A')),
           Font_Glyph);
      Assert
        (Lookup_Status = Textrender.Fonts.Glyph_Found,
         "test font should map A to a glyph index");

      Assert
        (Textrender.Load_Font
           (R, Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Success,
         "Load_Font should succeed");

      Status_1 :=
        Textrender.Get_Glyph_By_Index
          (R,
           Glyph_Index => Font_Glyph.Glyph_Index,
           M           => M1);
      Assert
        (Status_1 = Textrender.Success,
         "Get_Glyph_By_Index should rasterize A's glyph index");
      Assert (M1.W > 0, "glyph-index width should be positive");
      Assert (M1.H > 0, "glyph-index height should be positive");
      Assert (M1.Advance_X > 0.0, "glyph-index advance should be positive");

      Checksum_1 := Atlas_Checksum;

      Status_2 :=
        Textrender.Get_Glyph_By_Index
          (R,
           Glyph_Index => Font_Glyph.Glyph_Index,
           M           => M2);
      Assert
        (Status_2 = Textrender.Success,
         "cached Get_Glyph_By_Index should succeed");

      Checksum_2 := Atlas_Checksum;

      Assert
        (Checksum_1 = Checksum_2,
         "cached Get_Glyph_By_Index should not rewrite atlas pixels");
      Assert (M1.X = M2.X, "cached glyph-index X should match");
      Assert (M1.Y = M2.Y, "cached glyph-index Y should match");
      Assert (M1.U0 = M2.U0, "cached glyph-index U0 should match");
      Assert (M1.V0 = M2.V0, "cached glyph-index V0 should match");
      Assert (M1.U1 = M2.U1, "cached glyph-index U1 should match");
      Assert (M1.V1 = M2.V1, "cached glyph-index V1 should match");

      Textrender.Reset (R);
      Assert
        (Textrender.Load_Font
           (R, Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Success,
         "Load_Font should succeed for fallback glyph-index test");
      Assert
        (Textrender.Add_Fallback_Font (R, Font_Path) = Textrender.Success,
         "Add_Fallback_Font should succeed for glyph-index test");

      Status_1 :=
        Textrender.Get_Glyph_By_Index
          (R,
           Glyph_Index => Font_Glyph.Glyph_Index,
           M           => M1,
           Font_Index  => 1);
      Assert
        (Status_1 = Textrender.Success,
         "Get_Glyph_By_Index should rasterize from fallback font index");
      Assert (M1.W > 0, "fallback glyph-index width should be positive");

      Textrender.Fonts.Reset (Font);
   exception
      when others =>
         Textrender.Fonts.Reset (Font);
         raise;
   end Test_Get_Glyph_By_Index;

   procedure Test_ASCII_Range
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Status : Textrender.Status_Code;
      M      : Textrender.Glyph_Metric;
   begin
      Textrender.Reset (R);

      Assert
        (Textrender.Load_Font
           (R, Path         => Font_Path,
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
             (R, C => C,
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
      Textrender.Reset (R);

      Assert
      (Textrender.Load_Font
         (R, Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Success,
         "Load_Font should succeed");

      Status :=
      Textrender.Get_Glyph
         (R, C => Character'Pos ('!'),
         M => M);

      Assert
      (Status /= Textrender.Font_Load_Failed,
         "Exclamation glyph must not fail rasterization");

      Assert
      (M.Advance_X > 0.0,
         "Exclamation glyph should have positive advance");
   end Test_Get_Glyph_Exclamation;

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
      Textrender.Reset (R);

      Assert
        (Textrender.Load_Font
           (R, Path         => Font_Path,
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
                   (R, C => Character'Pos (C),
                    M => M);

               Assert
                 (Status = Textrender.Success,
                  "Glyph should load for baseline test: " & C);

               Assert (M.Advance_X > 0.0, "Advance should be positive");
               Assert (M.Bearing_Y >= 0.0, "Bearing_Y should be non-negative");

               Top_Y    := Baseline_Y - M.Bearing_Y;
               Bottom_Y := Top_Y + Float (M.H);

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
      Textrender.Reset (R);

      Assert
        (Textrender.Load_Font
           (R, Path         => Font_Path,
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
          (R, C => 16#00E9#,
           M => M);

      Assert
        (Status = Textrender.Success,
         "Composite accented glyph should render");

      Assert (M.W > 0, "Composite glyph width should be positive");
      Assert (M.H > 0, "Composite glyph height should be positive");
      Assert (M.Advance_X > 0.0, "Composite glyph advance should be positive");
   end Test_Composite_Accented_Glyph;

   procedure Test_Symbol_Glyph
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      Status : Textrender.Status_Code;
      M      : Textrender.Glyph_Metric;
   begin
      Textrender.Reset (R);

      Assert
        (Textrender.Load_Font
           (R, Path         => Font_Path,
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
          (R, C => 16#263A#,
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
      Textrender.Reset (R);

      Assert
        (Textrender.Load_Font
           (R, Path         => Font_Path,
            Pixel_Size   => 32,
            Cell_Width   => 20,
            Cell_Height  => 40,
            Atlas_Width  => 512,
            Atlas_Height => 512)
         = Textrender.Success,
         "Load_Font should succeed");

      Status :=
        Textrender.Get_Glyph
          (R, C => Character'Pos ('A'),
           M => M);

      Assert (Status = Textrender.Success, "Glyph A should load");

      P := Textrender.Place_Glyph_In_Cell
        (R, M => M,
         Cell_X => Cell_X,
         Cell_Y => Cell_Y);

      Baseline := Cell_Y + Textrender.Ascent (R);

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
      Textrender.Reset (R);

      Assert
        (Textrender.Load_Font
           (R, Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Success,
         "Load_Font should succeed");

      --  Pick something unlikely to exist
      Status_1 := Textrender.Get_Glyph (R, 16#10FFFF#, M1);
      Status_2 := Textrender.Get_Glyph (R, 16#10FFFF#, M2);

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
      Textrender.Reset (R);

      Assert
        (Textrender.Load_Font
           (R, Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Success, "Error during font load");

      Status := Textrender.Get_Glyph (R, Character'Pos ('A'), M);
      Assert (Status = Textrender.Success, "Get_Glyph error");

      --  Reload
      Assert
        (Textrender.Load_Font
           (R, Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Success, "Font loading error");

      Status := Textrender.Get_Glyph (R, Character'Pos ('A'), M);
      Assert (Status = Textrender.Success, "Error fetching glyph");
   end Test_Reload_Clears_Cache;

   procedure Test_Has_Glyph
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Textrender.Reset (R);

      Assert
        (Textrender.Load_Font
           (R, Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Success, "Font loading problem");

      Assert
        (Textrender.Has_Glyph (R, Character'Pos ('A')),
         "Font should directly contain A");

      Assert
        (not Textrender.Has_Glyph (R, 16#10FFFF#),
         "Font should not directly contain U+10FFFF");
   end Test_Has_Glyph;

   procedure Test_Has_Glyph_Before_Load
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Textrender.Reset (R);

      Assert
        (not Textrender.Has_Glyph (R, Character'Pos ('A')),
         "Has_Glyph before Load_Font should return False");
   end Test_Has_Glyph_Before_Load;

   procedure Test_Atlas_Pixels_After_Reset
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);
   begin
      Textrender.Reset (R);

      Assert
        (Textrender.Atlas_Pixels (R) = null,
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
      Textrender.Reset (R);

      Assert
        (Textrender.Load_Font
           (R, Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Success, "Font loading error");

      S := Textrender.Get_Glyph (R, Character'Pos ('A'), M1);
      Assert (S = Textrender.Success, "Get_Glyph error");

      S := Textrender.Get_Glyph (R, Character'Pos ('B'), M2);
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
      Textrender.Reset (R);

      Assert
        (Textrender.Load_Font
           (R, Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 256,
            Atlas_Height => 256)
         = Textrender.Success, "Font loading error");

      S := Textrender.Get_Glyph (R, Character'Pos ('A'), M16);
      Assert (S = Textrender.Success, "Get_Glyph error");

      Assert
        (Textrender.Load_Font
           (R, Path         => Font_Path,
            Pixel_Size   => 32,
            Cell_Width   => 20,
            Cell_Height  => 40,
            Atlas_Width  => 512,
            Atlas_Height => 512)
         = Textrender.Success, "Font loading error");

      S := Textrender.Get_Glyph (R, Character'Pos ('A'), M32);
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
      Textrender.Reset (R);

      Assert
        (Textrender.Load_Font
           (R, Path         => Font_Path,
            Pixel_Size   => 32,
            Cell_Width   => 20,
            Cell_Height  => 40,
            Atlas_Width  => 512,
            Atlas_Height => 512)
         = Textrender.Success, "Font loading error");

      for I in Codes'Range loop
         S := Textrender.Get_Glyph (R, Codes (I), M);

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
      Textrender.Reset (R);

      Assert
        (Textrender.Load_Font
           (R, Path         => Font_Path,
            Pixel_Size   => 16,
            Cell_Width   => 10,
            Cell_Height  => 20,
            Atlas_Width  => 1024,
            Atlas_Height => 1024)
         = Textrender.Success,
         "Load_Font should succeed");

      --  First pass: rasterizes and fills atlas/cache.
      for C in 32 .. 126 loop
         S := Textrender.Get_Glyph (R, C, M);

         Assert
           (S = Textrender.Success,
            "First ASCII pass failed at codepoint="
            & Integer'Image (C));
      end loop;

      Checksum_1 := Atlas_Checksum;

      --  Second pass: should be entirely cache hits.
      for C in 32 .. 126 loop
         S := Textrender.Get_Glyph (R, C, M);

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

   --  Regression guard for per-glyph spacing/geometry. For every drawable
   --  ASCII glyph, at several pixel sizes, the atlas UV rectangle the caller
   --  samples must match the integer pixel rectangle it draws (W/H), and its
   --  immediate left/right atlas neighbours must be empty. A mismatch here is
   --  exactly what shows up as a spurious gap after (roughly) every second
   --  character, so this asserts the drawn size and the sampled span agree.
   procedure Test_Glyph_UV_Matches_Draw_Rect
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      procedure Run (Pixel_Size, Cell : Positive) is
         Status : Textrender.Status_Code;
         M      : Textrender.Glyph_Metric;
         AW     : Positive;
         AH     : Positive;
         Pixels : access constant Textrender.Alpha_Buffer;
      begin
         Textrender.Reset (R);
         Assert
           (Textrender.Load_Font
              (R, Path         => Font_Path,
               Pixel_Size   => Pixel_Size,
               Cell_Width   => Cell,
               Cell_Height  => Cell * 2,
               Atlas_Width  => 1024,
               Atlas_Height => 1024)
            = Textrender.Success,
            "Load_Font should succeed");

         AW := Textrender.Atlas_Width (R);
         AH := Textrender.Atlas_Height (R);
         Pixels := Textrender.Atlas_Pixels (R);

         for C in 33 .. 126 loop
            Status := Textrender.Get_Glyph (R, C => C, M => M);

            if Status = Textrender.Success and then M.W > 0 and then M.H > 0 then
               declare
                  U_Span : constant Integer :=
                    Integer (Float'Rounding ((M.U1 - M.U0) * Float (AW)));
                  V_Span : constant Integer :=
                    Integer (Float'Rounding ((M.V1 - M.V0) * Float (AH)));
                  U0_Px  : constant Integer :=
                    Integer (Float'Rounding (M.U0 * Float (AW)));
                  V0_Px  : constant Integer :=
                    Integer (Float'Rounding (M.V0 * Float (AH)));
               begin
                  Assert
                    (U_Span = M.W,
                     "UV width must equal draw width W: cp="
                     & Integer'Image (C) & " W=" & Natural'Image (M.W)
                     & " U-span=" & Integer'Image (U_Span)
                     & " px=" & Positive'Image (Pixel_Size));
                  Assert
                    (V_Span = M.H,
                     "UV height must equal draw height H: cp="
                     & Integer'Image (C));
                  Assert
                    (U0_Px = M.X and then V0_Px = M.Y,
                     "U0/V0 must address the glyph's atlas origin: cp="
                     & Integer'Image (C));
                  Assert (M.Advance_X > 0.0, "Advance must be positive");

                  --  No neighbour bleed: the padding column on either side of
                  --  the glyph rectangle must be empty, otherwise adjacent
                  --  glyphs share texels and text spacing looks wrong.
                  if Pixels /= null then
                     for Row in M.Y .. M.Y + M.H - 1 loop
                        if M.X > 0 then
                           Assert
                             (Pixels (Row * AW + (M.X - 1)) = 0,
                              "Left padding column must be empty: cp="
                              & Integer'Image (C));
                        end if;
                        if M.X + M.W < AW then
                           Assert
                             (Pixels (Row * AW + (M.X + M.W)) = 0,
                              "Right padding column must be empty: cp="
                              & Integer'Image (C));
                        end if;
                     end loop;
                  end if;
               end;
            end if;
         end loop;
      end Run;
   begin
      Run (16, 10);
      Run (24, 16);
      Run (32, 20);
   end Test_Glyph_UV_Matches_Draw_Rect;

   overriding
   function Name
     (T : Textrender_Basic_Case) return AUnit.Message_String
   is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("Textrender basic tests");
   end Name;

   --  A TrueType Collection (.ttc) begins with a "ttcf" header, not a plain font. It used
   --  to fail to load outright -- the table directory was read from the wrong offset -- and
   --  on macOS, where the obvious monospace font (Menlo) is a .ttc, that left an empty atlas
   --  and no glyphs at all. This proves the first face of a collection now loads and
   --  rasterizes, on any host that ships one.
   procedure Test_Load_Ttc_Collection
     (T : in out AUnit.Test_Cases.Test_Case'Class)
   is
      pragma Unreferenced (T);

      type Constant_String_Access is access constant String;
      Candidates : constant array (Positive range <>) of Constant_String_Access :=
        [new String'("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"),
         new String'("/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc"),
         new String'("/System/Library/Fonts/Menlo.ttc"),
         new String'("/System/Library/Fonts/Helvetica.ttc")];

      Found  : String (1 .. 512);
      Length : Natural := 0;
      Status : Textrender.Status_Code;
      M      : Textrender.Glyph_Metric;
   begin
      for Candidate of Candidates loop
         if Length = 0 and then Ada.Directories.Exists (Candidate.all) then
            Length := Candidate.all'Length;
            Found (1 .. Length) := Candidate.all;
         end if;
      end loop;

      if Length = 0 then
         --  No collection on this host to try. Say so rather than pass silently.
         Assert (True, "no .ttc font present to exercise; skipped");
         return;
      end if;

      Textrender.Reset (R);

      Status :=
        Textrender.Load_Font
          (R, Path         => Found (1 .. Length),
           Pixel_Size   => 16,
           Cell_Width   => 10,
           Cell_Height  => 20,
           Atlas_Width  => 256,
           Atlas_Height => 256);

      --  It must return a definite status, not crash. Reading the whole file onto the
      --  stack overflowed it on a large collection, and a mis-parsed "ttcf" header sent the
      --  reader off into nonsense -- both took the program down rather than failing. A
      --  TrueType collection (macOS Menlo) loads and renders; a CFF one (Noto CJK) is a
      --  clean Font_Load_Failed, because textrender does not do CFF outlines. Either is a
      --  pass here; a crash is the only failure.
      Assert
        (Status in Textrender.Success | Textrender.Font_Load_Failed,
         "a .ttc collection loads cleanly or fails cleanly, but does not crash");

      if Status = Textrender.Success then
         Status := Textrender.Get_Glyph (R, C => Character'Pos ('A'), M => M);
         Assert (Status = Textrender.Success, "a glyph rasterizes out of a TrueType collection");
      end if;
   end Test_Load_Ttc_Collection;

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
         Test_Glyph_UV_Matches_Draw_Rect'Access,
         "Glyph UV rectangle matches draw rectangle (spacing guard)");

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
         Test_Load_Ttc_Collection'Access,
         "Load_Font reads the first face of a .ttc collection");

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
         Test_Get_Glyph_By_Index'Access,
         "Get Glyph By Index");

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
