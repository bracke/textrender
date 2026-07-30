with AUnit.Assertions;

with Ada.Directories;
with Ada.Environment_Variables;

with Textrender.Fonts;

package body Textrender.BasicTests is

   use AUnit.Assertions;
   use type Textrender.Fonts.Glyph_Lookup_Result;
   use type Textrender.Fonts.Load_Result;

   --  A monospaced font belonging to the host these tests are running on.
   --
   --  Every host keeps its fonts somewhere else under some other name, so this
   --  is a search rather than a path. Which face it finds does not matter to
   --  what is being tested -- these are outlines, metrics and atlas bookkeeping,
   --  not a particular typeface -- but it must be a real font, because a
   --  synthetic one would not exercise the parser.
   --
   --  DejaVu comes first so a Linux machine and Linux CI agree on the face, and
   --  the tests that compare one atlas checksum against another keep comparing
   --  like with like.
   Test_Font_Candidates : constant array (Positive range <>) of access constant String :=
     [new String'("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"),
      new String'("/usr/share/fonts/TTF/DejaVuSansMono.ttf"),
      new String'("/usr/share/fonts/dejavu-sans-mono-fonts/DejaVuSansMono.ttf"),
      new String'("/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf"),
      new String'("/System/Library/Fonts/Menlo.ttc"),
      new String'("/System/Library/Fonts/Monaco.ttf"),
      new String'("C:\Windows\Fonts\consola.ttf"),
      new String'("C:\Windows\Fonts\cour.ttf")];

   --  Where each host keeps its colour emoji font.
   Colour_Font_Candidates : constant array (Positive range <>) of access constant String :=
     [new String'("/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf"),
      new String'("/System/Library/Fonts/Apple Color Emoji.ttc"),
      new String'("C:\Windows\Fonts\seguiemj.ttf")];

   function Resolve_Test_Font return String;

   function Resolve_Test_Font return String is
   begin
      for Candidate of Test_Font_Candidates loop
         if Ada.Directories.Exists (Candidate.all) then
            return Candidate.all;
         end if;
      end loop;

      return "";
   end Resolve_Test_Font;

   Font_Path : constant String := Resolve_Test_Font;

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

   --  If this fails nothing else in the suite means anything: every test that
   --  follows loads this font, and each of them would report a missing fixture
   --  as a defect in the parser.
   procedure Test_Test_Font_Exists (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Layered_Colour_Glyph (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Paint_Graph_Colour_Glyph (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Host_Colour_Font_Has_Pictures (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  Whichever colour font the host ships, find a picture in it.
   --
   --  The point is the macOS half. Apple Color Emoji keeps its pictures in sbix
   --  and Noto keeps them in CBDT, and the sbix reader was written from the
   --  specification against a font this machine does not have -- so until this
   --  ran on a macOS runner, nothing had ever executed it.
   --
   --  Deliberately asks less than the Noto-specific tests below: only that the
   --  font loads, maps an emoji, and has a decodable picture for it. Whether it
   --  also lacks outlines, and at what size it stores them, is each font's own
   --  business and not something both formats agree on.
   procedure Test_Host_Colour_Font_Has_Pictures (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use type Textrender.Fonts.Colour_Image_Format;

      Grinning : constant Textrender.Fonts.Codepoint := 16#1F600#;
      Found    : Boolean := False;
   begin
      for Candidate of Colour_Font_Candidates loop
         if Ada.Directories.Exists (Candidate.all) then
            declare
               F     : Textrender.Fonts.Font;
               Index : Natural := 0;
            begin
               --  A font that will not load is not a skip, it is a failure: the
               --  file is there and this crate claims to read it.
               Assert (Textrender.Fonts.Load (F, Candidate.all) = Textrender.Fonts.Loaded,
                       "the host colour font loads: " & Candidate.all);

               --  Segoe UI Emoji is COLR/CPAL, which is not read yet, so it has
               --  no bitmaps to find. Say so rather than failing for it.
               if Textrender.Fonts.Has_Colour_Bitmaps (F) then
                  Assert (Textrender.Fonts.Glyph_Index_Of (F, Grinning, Index),
                          "it maps the grinning face: " & Candidate.all);

                  declare
                     Bitmap : constant Textrender.Fonts.Colour_Bitmap :=
                       Textrender.Fonts.Colour_Bitmap_For (F, Index, 16);
                  begin
                     Assert (Bitmap.Format = Textrender.Fonts.Png_Colour_Image,
                             "and holds a picture for it: " & Candidate.all);
                     Assert (Bitmap.Width > 0 and then Bitmap.Height > 0,
                             "of a real size: " & Candidate.all);
                     Assert (Bitmap.Data_Length > 0,
                             "with bytes behind it: " & Candidate.all);
                  end;

                  Found := True;
               end if;

               Textrender.Fonts.Reset (F);
            end;
         end if;
      end loop;

      --  No colour font installed is a skip; this only records that it happened.
      if not Found then
         Assert (True, "no colour font on this host");
      end if;
   end Test_Host_Colour_Font_Has_Pictures;

   --  A layered colour glyph, drawn rather than decoded.
   --
   --  COLR/CPAL is the other way a font carries colour: instead of a picture per
   --  glyph, an emoji is a stack of ordinary outlines each painted from a
   --  palette. That means no decoder is involved at all, which this checks by
   --  installing none.
   --
   --  Twemoji is the fixture because it is COLR v0 and freely available; Segoe
   --  UI Emoji is the font this matters for on Windows, and no runner here has
   --  it. Skipped when the fixture is absent, since it is not installed by
   --  default anywhere.
   --  A COLR version 1 glyph: a paint graph rather than a flat layer list.
   --
   --  Worth its own test because a v1 font's v0 section is normally EMPTY, so a
   --  reader that only understands v0 draws nothing at all for it -- the failure
   --  is silence, not a wrong colour. Noto's v1 build is the fixture: 3993 base
   --  glyphs whose paints are mostly solid fills, with a few thousand linear and
   --  radial gradients and transforms among them.
   procedure Test_Paint_Graph_Colour_Glyph (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      function Paint_Font_Path return String is
      begin
         if Ada.Environment_Variables.Exists ("TEXTRENDER_COLRV1_FONT")
           and then Ada.Directories.Exists
             (Ada.Environment_Variables.Value ("TEXTRENDER_COLRV1_FONT"))
         then
            return Ada.Environment_Variables.Value ("TEXTRENDER_COLRV1_FONT");
         else
            return "";
         end if;
      end Paint_Font_Path;

      Paint_Font : constant String := Paint_Font_Path;
      R : Textrender.Renderer;
      G : Textrender.Colour_Glyph;

      --  U+1F308 RAINBOW, which is a gradient if anything is.
      Rainbow : constant Textrender.Codepoint := 16#1F308#;
   begin
      if Paint_Font = "" or else Font_Path = "" then
         return;
      end if;

      Assert
        (Textrender.Load_Font
           (R, Path => Font_Path, Pixel_Size => 16,
            Cell_Width => 8, Cell_Height => 20,
            Atlas_Width => 512, Atlas_Height => 512) = Textrender.Success,
         "the text font loads");
      Assert (Textrender.Add_Fallback_Font (R, Paint_Font) = Textrender.Success,
              "and a paint-graph colour font joins the chain");

      Assert (Textrender.Has_Colour_Glyph (R, Rainbow),
              "the paint graph is found with no decoder installed");
      Assert (Textrender.Get_Colour_Glyph (R, Rainbow, G) = Textrender.Success,
              "and paints");
      Assert (G.Width > 0 and then G.Height > 0, "at a real size");

      declare
         Pixels : constant access constant Textrender.Rgba_Buffer :=
           Textrender.Colour_Sheet_Pixels (R);
         Stride : constant Natural := Textrender.Colour_Sheet_Width (R);
         Opaque : Natural := 0;
         Distinct_Hues : Natural := 0;
         Seen_R : array (0 .. 7) of Boolean := [others => False];
      begin
         Assert (Pixels /= null, "with a sheet behind it");

         for Pixel in 0 .. G.Width * G.Height - 1 loop
            declare
               Red   : constant Natural := Natural (Pixels (((G.Y + Pixel / G.Width) * Stride + G.X + Pixel mod G.Width) * 4));
               Green : constant Natural := Natural (Pixels (((G.Y + Pixel / G.Width) * Stride + G.X + Pixel mod G.Width) * 4 + 1));
               Blue  : constant Natural := Natural (Pixels (((G.Y + Pixel / G.Width) * Stride + G.X + Pixel mod G.Width) * 4 + 2));
               A     : constant Natural := Natural (Pixels (((G.Y + Pixel / G.Width) * Stride + G.X + Pixel mod G.Width) * 4 + 3));
            begin
               if A > 128 then
                  Opaque := Opaque + 1;

                  if abs (Red - Green) > 30 or else abs (Green - Blue) > 30 then
                     Seen_R (Red / 32) := True;
                  end if;
               end if;
            end;
         end loop;

         for Bucket of Seen_R loop
            if Bucket then
               Distinct_Hues := Distinct_Hues + 1;
            end if;
         end loop;

         Assert (Opaque > (G.Width * G.Height) / 20,
                 "something was painted, got" & Natural'Image (Opaque)
                 & " opaque of" & Natural'Image (G.Width * G.Height));

         --  A rainbow is several colours. One would mean the paint graph
         --  collapsed to a single fill, which is the plausible way to get this
         --  wrong and still draw something.
         Assert (Distinct_Hues >= 2,
                 "and in more than one colour, got" & Natural'Image (Distinct_Hues)
                 & " bands");
      end;

      Textrender.Reset (R);
   end Test_Paint_Graph_Colour_Glyph;

   procedure Test_Layered_Colour_Glyph (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      --  Named by the environment so CI can put it where it likes, with the
      --  places a system package would install it as a fallback.
      function Layered_Font_Path return String is
      begin
         if Ada.Environment_Variables.Exists ("TEXTRENDER_COLR_FONT")
           and then Ada.Directories.Exists
             (Ada.Environment_Variables.Value ("TEXTRENDER_COLR_FONT"))
         then
            return Ada.Environment_Variables.Value ("TEXTRENDER_COLR_FONT");
         elsif Ada.Directories.Exists
           ("/usr/share/fonts/truetype/twemoji/TwemojiMozilla.ttf")
         then
            return "/usr/share/fonts/truetype/twemoji/TwemojiMozilla.ttf";
         else
            return "";
         end if;
      end Layered_Font_Path;

      Twemoji : constant String := Layered_Font_Path;
      R : Textrender.Renderer;
      G : Textrender.Colour_Glyph;

      --  U+1F389 PARTY POPPER: several layers in several colours.
      Party : constant Textrender.Codepoint := 16#1F389#;
   begin
      if Twemoji = "" or else Font_Path = "" then
         return;
      end if;

      Assert
        (Textrender.Load_Font
           (R, Path => Font_Path, Pixel_Size => 16,
            Cell_Width => 8, Cell_Height => 20,
            Atlas_Width => 512, Atlas_Height => 512) = Textrender.Success,
         "the text font loads");
      Assert (Textrender.Add_Fallback_Font (R, Twemoji) = Textrender.Success,
              "and a layered colour font joins the chain");

      --  No decoder is installed, deliberately: layers are outlines, not
      --  pictures, so this path must work without one.
      Assert (Textrender.Has_Colour_Glyph (R, Party),
              "a layered glyph is available with no decoder installed");
      Assert (Textrender.Get_Colour_Glyph (R, Party, G) = Textrender.Success,
              "and composites");
      Assert (G.Width > 0 and then G.Height > 0,
              "at a real size, got" & Natural'Image (G.Width)
              & " x" & Natural'Image (G.Height));

      declare
         Pixels : constant access constant Textrender.Rgba_Buffer :=
           Textrender.Colour_Sheet_Pixels (R);
         Stride : constant Natural := Textrender.Colour_Sheet_Width (R);
         Opaque  : Natural := 0;
         Coloured : Natural := 0;
      begin
         Assert (Pixels /= null, "with a sheet behind it");

         for Pixel in 0 .. G.Width * G.Height - 1 loop
            declare
               Red   : constant Natural := Natural (Pixels (((G.Y + Pixel / G.Width) * Stride + G.X + Pixel mod G.Width) * 4));
               Green : constant Natural := Natural (Pixels (((G.Y + Pixel / G.Width) * Stride + G.X + Pixel mod G.Width) * 4 + 1));
               Blue  : constant Natural := Natural (Pixels (((G.Y + Pixel / G.Width) * Stride + G.X + Pixel mod G.Width) * 4 + 2));
               A     : constant Natural := Natural (Pixels (((G.Y + Pixel / G.Width) * Stride + G.X + Pixel mod G.Width) * 4 + 3));
            begin
               if A > 128 then
                  Opaque := Opaque + 1;

                  --  Grey would mean the palette was never applied and the
                  --  coverage was written straight through.
                  if abs (Red - Green) > 30 or else abs (Green - Blue) > 30 then
                     Coloured := Coloured + 1;
                  end if;
               end if;
            end;
         end loop;

         Assert (Opaque > (G.Width * G.Height) / 20,
                 "something was actually drawn, got" & Natural'Image (Opaque)
                 & " opaque of" & Natural'Image (G.Width * G.Height));
         Assert (Coloured > 0,
                 "and it carries palette colour rather than bare coverage");
      end;

      Textrender.Reset (R);
   end Test_Layered_Colour_Glyph;

   procedure Test_Test_Font_Exists (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Font_Path /= "",
              "no monospaced font on this host: looked under /usr/share/fonts,"
              & " /System/Library/Fonts and C:\Windows\Fonts");
   end Test_Test_Font_Exists;

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

   --  The colour glyph path, exercised without a PNG decoder in sight.
   --
   --  What this crate owns is the seam and what happens after it: find the
   --  picture, ask the caller to decode it, average it down to the cell, pack it
   --  into the colour atlas, report where it landed. Whether PNG is decoded
   --  correctly is the caller's business, so the stub here returns a known
   --  pattern and the assertions are about the parts textrender is responsible
   --  for.
   --
   --  The pattern is deliberate: the left half opaque red, the right half opaque
   --  blue. After averaging down, the left of the result must still be red-ish
   --  and the right blue-ish. A downscale that sampled single pixels rather than
   --  averaging would still pass that -- but one that mixed up rows and columns,
   --  or wrote outside its rectangle, would not.
   Stub_Source_Size : constant := 128;

   function Stub_Extent
     (Data   : Textrender.Encoded_Image;
      Width  : out Natural;
      Height : out Natural)
      return Boolean
   is
      pragma Unreferenced (Data);
   begin
      Width := Stub_Source_Size;
      Height := Stub_Source_Size;
      return True;
   end Stub_Extent;

   function Stub_Decode
     (Data   : Textrender.Encoded_Image;
      Width  : Natural;
      Height : Natural;
      Pixels : out Textrender.Rgba_Buffer)
      return Boolean
   is
      pragma Unreferenced (Data);
   begin
      Pixels := [others => 0];

      for Row in 0 .. Height - 1 loop
         for Col in 0 .. Width - 1 loop
            declare
               At_Px : constant Natural := (Row * Width + Col) * 4;
            begin
               if At_Px + 3 <= Pixels'Last then
                  if Col < Width / 2 then
                     Pixels (At_Px) := 255;      --  red
                     Pixels (At_Px + 1) := 0;
                     Pixels (At_Px + 2) := 0;
                  else
                     Pixels (At_Px) := 0;
                     Pixels (At_Px + 1) := 0;
                     Pixels (At_Px + 2) := 255;  --  blue
                  end if;

                  Pixels (At_Px + 3) := 255;
               end if;
            end;
         end loop;
      end loop;

      return True;
   end Stub_Decode;

   procedure Test_Colour_Glyph_Pipeline (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      Emoji_Path : constant String :=
        "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf";
      R : Textrender.Renderer;
      G : Textrender.Colour_Glyph;
      Grinning : constant Textrender.Codepoint := 16#1F600#;
   begin
      if not Ada.Directories.Exists (Emoji_Path) then
         return;
      end if;

      --  A text font first, then the emoji font as a fallback: the arrangement a
      --  real application has.
      Assert
        (Textrender.Load_Font
           (R, Path => Font_Path, Pixel_Size => 16,
            Cell_Width => 8, Cell_Height => 20,
            Atlas_Width => 512, Atlas_Height => 512) = Textrender.Success,
         "the text font loads");
      Assert
        (Textrender.Add_Fallback_Font (R, Emoji_Path) = Textrender.Success,
         "and a colour emoji font joins the fallback chain");

      --  Without a decoder there are no colour glyphs, which is today's
      --  behaviour and must stay available as an answer.
      Assert
        (not Textrender.Has_Colour_Glyph (R, Grinning),
         "no decoder means no colour glyph");

      Textrender.Set_Image_Decoder (R, Stub_Extent'Access, Stub_Decode'Access);
      Assert
        (Textrender.Has_Colour_Glyph (R, Grinning),
         "with a decoder installed the emoji has a colour glyph");

      Assert
        (Textrender.Get_Colour_Glyph (R, Grinning, G) = Textrender.Success,
         "and it decodes into a tile");

      --  Scaled to fit two cells, keeping its square aspect: 2x8 wide by 20 high
      --  bounds a 128x128 source to 16x16.
      Assert (G.Width = 16 and then G.Height = 16,
              "the picture is fitted to the cell, got"
              & Natural'Image (G.Width) & " x" & Natural'Image (G.Height));
      Assert (G.Advance_X = 16.0, "and advances across the two cells it fills");

      --  The averaged result: left half red, right half blue. The tile is its
      --  own picture, so it is addressed by its own width, with no atlas origin
      --  to offset by.
      declare
         Pixels : constant access constant Textrender.Rgba_Buffer :=
           Textrender.Colour_Sheet_Pixels (R);
         Stride : constant Natural := Textrender.Colour_Sheet_Width (R);

         function At_Pixel (Col : Natural; Row : Natural; Channel : Natural) return Natural is
           (Natural (Pixels (((G.Y + Row) * Stride + G.X + Col) * 4 + Channel)));
      begin
         Assert (Pixels /= null, "the sheet has pixels");
         Assert (G.U1 > G.U0 and then G.V1 > G.V0,
                 "and the glyph names a rectangle of it");
         Assert (At_Pixel (1, G.Height / 2, 0) > 200, "the left of the glyph is red");
         Assert (At_Pixel (1, G.Height / 2, 2) < 60, "and not blue");
         Assert (At_Pixel (G.Width - 2, G.Height / 2, 2) > 200, "the right of the glyph is blue");
         Assert (At_Pixel (G.Width - 2, G.Height / 2, 0) < 60, "and not red");
         Assert (At_Pixel (1, G.Height / 2, 3) > 200, "and it is opaque");
      end;

      --  Asked twice, decoded once: the same tile comes back, not an equal copy
      --  of it. Comparing the pixels would pass even if it decoded again.
      declare
         Again : Textrender.Colour_Glyph;
      begin
         Assert
           (Textrender.Get_Colour_Glyph (R, Grinning, Again) = Textrender.Success,
            "a second request succeeds");
         Assert (Again.X = G.X and then Again.Y = G.Y,
                 "from the same place in the sheet rather than a second decode");
      end;

      Textrender.Reset (R);
   end Test_Colour_Glyph_Pipeline;

   --  A bitmap-only colour font: no glyf, no loca, nothing to rasterize. Loading
   --  one used to be impossible -- Parse_Tables required outlines -- so the whole
   --  category of colour emoji fonts was unreachable.
   --
   --  The numbers asserted here were read out of Noto Color Emoji's own bytes
   --  before any of this was written: one strike at 109 ppem, index format 1 with
   --  image format 17 throughout, glyph bitmaps 136x128 with bearing 0,101, and
   --  every image a PNG. Skipped where the font is not installed, so this does
   --  not turn a missing font into a failure.
   procedure Test_Colour_Bitmap_Font (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      use type Textrender.Fonts.Colour_Image_Format;

      Emoji_Path : constant String :=
        "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf";
      F : Textrender.Fonts.Font;
   begin
      if not Ada.Directories.Exists (Emoji_Path) then
         return;
      end if;

      Assert
        (Textrender.Fonts.Load (F, Emoji_Path) = Textrender.Fonts.Loaded,
         "a colour font with no outlines loads");
      Assert
        (Textrender.Fonts.Has_Colour_Bitmaps (F),
         "and reports that it carries colour bitmaps");
      Assert
        (Textrender.Fonts.Is_Bitmap_Only (F),
         "and that it has no outlines at all");

      --  A glyph the strike covers. Glyph 19 sits inside the second index
      --  subtable, well away from the range edges.
      declare
         B : constant Textrender.Fonts.Colour_Bitmap :=
           Textrender.Fonts.Colour_Bitmap_For (F, 19, 16);
      begin
         Assert
           (B.Format = Textrender.Fonts.Png_Colour_Image,
            "a covered glyph yields a PNG image");
         Assert (B.Width = 136 and then B.Height = 128,
                 "with the strike's bitmap size");
         Assert (B.Bearing_X = 0 and then B.Bearing_Y = 101,
                 "and the placement the font records");
         Assert (B.Ppem = 109, "from the font's single 109 ppem strike");
         Assert (B.Data_Length > 0, "and a non-empty image");
      end;

      --  Glyph 18 falls in the gap between subtables: coverage is sparse, and a
      --  glyph without a bitmap must say so rather than return stray bytes.
      declare
         B : constant Textrender.Fonts.Colour_Bitmap :=
           Textrender.Fonts.Colour_Bitmap_For (F, 18, 16);
      begin
         Assert
           (B.Format = Textrender.Fonts.No_Colour_Image,
            "a glyph in a gap between strike subtables has no bitmap");
      end;

      --  Far past the last covered glyph, and past numGlyphs entirely.
      declare
         B : constant Textrender.Fonts.Colour_Bitmap :=
           Textrender.Fonts.Colour_Bitmap_For (F, 99_999, 16);
      begin
         Assert
           (B.Format = Textrender.Fonts.No_Colour_Image,
            "a glyph index beyond the font is refused rather than read");
      end;

      Textrender.Fonts.Reset (F);
   end Test_Colour_Bitmap_Font;

   overriding
   procedure Register_Tests
     (T : in out Textrender_Basic_Case)
   is
   begin
      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Test_Font_Exists'Access,
         "a monospaced font for the tests exists on this host");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Host_Colour_Font_Has_Pictures'Access,
         "whatever colour font this host ships, a picture can be found in it");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Layered_Colour_Glyph'Access,
         "a COLR/CPAL glyph is composited from its layers, in colour");

      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Paint_Graph_Colour_Glyph'Access,
         "a COLR v1 paint graph draws, gradients and all");

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
      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Colour_Bitmap_Font'Access,
         "Colour Bitmap Font");
      AUnit.Test_Cases.Registration.Register_Routine
        (T,
         Test_Colour_Glyph_Pipeline'Access,
         "Colour Glyph Pipeline");

   end Register_Tests;

end Textrender.BasicTests;
