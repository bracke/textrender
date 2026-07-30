with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Textrender.Fonts; use Textrender.Fonts;
with Textrender.Atlases;
with Textrender.Rasterizer;
with Ada.Containers; use Ada.Containers;
with Ada.Containers.Hashed_Maps;
with Ada.Containers.Vectors;
with Ada.Unchecked_Deallocation;

package body Textrender is

   type Cached_Glyph is record
      Status : Status_Code := Success;
      Metric : Glyph_Metric;
   end record;

   function Codepoint_Hash (C : Codepoint) return Hash_Type is
     (Hash_Type (C));

   type Glyph_Index_Key is record
      Font_Index  : Natural := 0;
      Glyph_Index : Natural := 0;
   end record;

   function Glyph_Index_Key_Hash (Key : Glyph_Index_Key) return Hash_Type is
     (Hash_Type (Key.Font_Index * 1_048_583 + Key.Glyph_Index));

   package Glyph_Caches is new Ada.Containers.Hashed_Maps
     (Key_Type        => Codepoint,
      Element_Type    => Cached_Glyph,
      Hash            => Codepoint_Hash,
      Equivalent_Keys => "=");

   package Glyph_Index_Caches is new Ada.Containers.Hashed_Maps
     (Key_Type        => Glyph_Index_Key,
      Element_Type    => Cached_Glyph,
      Hash            => Glyph_Index_Key_Hash,
      Equivalent_Keys => "=");

   Glyph_Padding : constant Natural := 1;

   --  Tangent of the slant angle. 0.0 = upright. ~0.21 corresponds to a
   --  12-degree oblique, a typical italic tilt.
   Italic_Slant_Tangent : constant Float := 0.21;

   function Slant_For (Style : Font_Style) return Float is
     (case Style is
        when Regular => 0.0,
        when Italic  => Italic_Slant_Tangent);

   --  Ordered fallback font chain. Each element is an additional font face
   --  that shares the renderer's single atlas; Get_Glyph consults the primary
   --  font first and then these in order. Fonts are non-limited records that
   --  merely reference their own byte buffer, so storing them by value here is
   --  a shallow copy; each is released with Textrender.Fonts.Reset on teardown.
   package Font_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Textrender.Fonts.Font);

   type Rgba_Buffer_Access is access all Rgba_Buffer;

   --  Colour glyphs already packed, by codepoint. The picture itself lives in
   --  the sheet; what is kept here is where in it, and the metrics.
   package Colour_Caches is new Ada.Containers.Hashed_Maps
     (Key_Type        => Codepoint,
      Element_Type    => Colour_Glyph,
      Hash            => Codepoint_Hash,
      Equivalent_Keys => "=");

   type Renderer_State is record
      Font          : Textrender.Fonts.Font;
      Fallbacks     : Font_Vectors.Vector;
      Atlas         : Textrender.Atlases.Atlas;
      Cache         : Glyph_Caches.Map;
      Italic_Cache  : Glyph_Caches.Map;
      Glyph_Index_Cache : Glyph_Index_Caches.Map;
      Italic_Glyph_Index_Cache : Glyph_Index_Caches.Map;
      Pixel_Size    : Positive := 1;
      Cell_Width_V  : Positive := 1;
      Cell_Height_V : Positive := 1;
      Atlas_Dirty_V : Boolean := False;

      --  Colour glyphs: where each one sits, and the sheet they sit in.
      --
      --  Packed here rather than by the caller because every caller that drew
      --  these packed them itself, and kept its own record of which codepoint
      --  had been packed -- duplicating the cache below.
      Colour_Cache  : Colour_Caches.Map;
      Colour_Sheet  : Rgba_Buffer_Access := null;
      Colour_Width  : Natural := 0;
      Colour_Height : Natural := 0;
      Colour_Dirty_V : Boolean := False;

      --  Shelf packing state: the pen, and how tall the current shelf is.
      Colour_Pen_X  : Natural := 0;
      Colour_Pen_Y  : Natural := 0;
      Colour_Shelf  : Natural := 0;

      --  The caller's decoder, or null for "colour glyphs unavailable".
      Extent_Reader : Image_Extent_Reader := null;
      Decoder       : Image_Decoder := null;
   end record;

   procedure Reset_Fallbacks (State : in out Renderer_State);

   procedure Reset_Fallbacks (State : in out Renderer_State) is
   begin
      for F of State.Fallbacks loop
         Textrender.Fonts.Reset (F);
      end loop;

      State.Fallbacks.Clear;
   end Reset_Fallbacks;

   procedure Free_Rgba is new Ada.Unchecked_Deallocation
     (Rgba_Buffer, Rgba_Buffer_Access);

   --  The sheet is one allocation; dropping the map without freeing it would
   --  leak, and keeping the map without the sheet would hand out coordinates
   --  into a picture that is gone.
   procedure Free_Colour_Cache (State : in out Renderer_State);

   procedure Free_Colour_Cache (State : in out Renderer_State) is
   begin
      Free_Rgba (State.Colour_Sheet);
      State.Colour_Sheet := null;
      State.Colour_Width := 0;
      State.Colour_Height := 0;
      State.Colour_Pen_X := 0;
      State.Colour_Pen_Y := 0;
      State.Colour_Shelf := 0;
      State.Colour_Dirty_V := False;
      State.Colour_Cache.Clear;
   end Free_Colour_Cache;

   procedure Free_State is new Ada.Unchecked_Deallocation
     (Renderer_State, Renderer_State_Access);

   procedure Ensure_State (R : in out Renderer) with Inline;

   procedure Ensure_State (R : in out Renderer) is
   begin
      if R.State = null then
         R.State := new Renderer_State;
      end if;
   end Ensure_State;

   -----------------------------
   --  Initialize / Finalize
   -----------------------------

   overriding procedure Initialize (R : in out Renderer) is
   begin
      R.State := new Renderer_State;
   end Initialize;

   overriding procedure Finalize (R : in out Renderer) is
   begin
      if R.State /= null then
         Textrender.Fonts.Reset (R.State.Font);
         Reset_Fallbacks (R.State.all);
         Textrender.Atlases.Reset (R.State.Atlas);
         R.State.Cache.Clear;
         R.State.Italic_Cache.Clear;
         R.State.Glyph_Index_Cache.Clear;
         R.State.Italic_Glyph_Index_Cache.Clear;
         Free_Colour_Cache (R.State.all);
         Free_State (R.State);
      end if;
   end Finalize;

   -----------------------------
   --  Reset
   -----------------------------

   procedure Reset (R : in out Renderer) is
   begin
      Ensure_State (R);

      Textrender.Fonts.Reset (R.State.Font);
      Reset_Fallbacks (R.State.all);
      Textrender.Atlases.Reset (R.State.Atlas);

      R.State.Cache.Clear;
      R.State.Italic_Cache.Clear;
      R.State.Glyph_Index_Cache.Clear;
      R.State.Italic_Glyph_Index_Cache.Clear;
      Free_Colour_Cache (R.State.all);

      R.State.Pixel_Size    := 1;
      R.State.Cell_Width_V  := 1;
      R.State.Cell_Height_V := 1;

      R.State.Atlas_Dirty_V := False;
   end Reset;

   -----------------------------
   --  Load_Font
   -----------------------------

   function Load_Font
     (R            : in out Renderer;
      Path         : String;
      Pixel_Size   : Positive;
      Cell_Width   : Positive;
      Cell_Height  : Positive;
      Atlas_Width  : Positive;
      Atlas_Height : Positive) return Status_Code
   is
      Result : Textrender.Fonts.Load_Result;
   begin
      Reset (R);

      Result := Textrender.Fonts.Load (R.State.Font, Path);

      if Result /= Textrender.Fonts.Loaded then
         return Font_Load_Failed;
      end if;

      R.State.Pixel_Size    := Pixel_Size;
      R.State.Cell_Width_V  := Cell_Width;
      R.State.Cell_Height_V := Cell_Height;

      Textrender.Atlases.Init
        (R.State.Atlas,
         Width  => Atlas_Width,
         Height => Atlas_Height);

      R.State.Atlas_Dirty_V := True;

      return Success;
   end Load_Font;

   -----------------------------
   --  Add_Fallback_Font
   -----------------------------

   function Add_Fallback_Font
     (R    : in out Renderer;
      Path : String) return Status_Code
   is
      New_Font : Textrender.Fonts.Font;
      Result   : Textrender.Fonts.Load_Result;
   begin
      Ensure_State (R);

      --  A primary font must be loaded first: it establishes the shared atlas,
      --  pixel size, and grid that every fallback rasterizes into.
      if not Textrender.Fonts.Loaded (R.State.Font) then
         return Font_Not_Loaded;
      end if;

      Result := Textrender.Fonts.Load (New_Font, Path);

      if Result /= Textrender.Fonts.Loaded then
         Textrender.Fonts.Reset (New_Font);
         return Font_Load_Failed;
      end if;

      R.State.Fallbacks.Append (New_Font);

      return Success;
   end Add_Fallback_Font;

   -----------------------------
   --  Metrics
   -----------------------------

   function Ascent (R : Renderer) return Float is
   begin
      return
        Float (Textrender.Fonts.Ascent (R.State.Font))
        * Float (R.State.Pixel_Size)
        / Float (Textrender.Fonts.Units_Per_Em (R.State.Font));
   end Ascent;

   function Descent (R : Renderer) return Float is
   begin
      return
        Float (Textrender.Fonts.Descent (R.State.Font))
        * Float (R.State.Pixel_Size)
        / Float (Textrender.Fonts.Units_Per_Em (R.State.Font));
   end Descent;

   function Line_Height (R : Renderer) return Float is
   begin
      return
        Float
          (Textrender.Fonts.Ascent (R.State.Font)
           - Textrender.Fonts.Descent (R.State.Font)
           + Textrender.Fonts.Line_Gap (R.State.Font))
        * Float (R.State.Pixel_Size)
        / Float (Textrender.Fonts.Units_Per_Em (R.State.Font));
   end Line_Height;

   function Cell_Width (R : Renderer) return Positive is
   begin
      return R.State.Cell_Width_V;
   end Cell_Width;

   function Cell_Height (R : Renderer) return Positive is
   begin
      return R.State.Cell_Height_V;
   end Cell_Height;

   function Has_Glyph (R : Renderer; C : Codepoint) return Boolean is
   begin
      return Textrender.Fonts.Has_Glyph (R.State.Font, C);
   end Has_Glyph;

   -----------------------------
   --  Get_Glyph
   -----------------------------

   function Get_Glyph
     (R     : in out Renderer;
      C     : Codepoint;
      M     : out Glyph_Metric;
      Style : Font_Style := Regular) return Status_Code
   is
      procedure Cache_Insert (Key : Codepoint; Item : Cached_Glyph) is
      begin
         case Style is
            when Regular => R.State.Cache.Insert (Key, Item);
            when Italic  => R.State.Italic_Cache.Insert (Key, Item);
         end case;
      end Cache_Insert;

      function Cache_Find (Key : Codepoint) return Glyph_Caches.Cursor is
        (case Style is
           when Regular => R.State.Cache.Find (Key),
           when Italic  => R.State.Italic_Cache.Find (Key));
      G : Textrender.Fonts.Glyph_Info;

      Lookup_Result : Textrender.Fonts.Glyph_Lookup_Result;

      --  The font in the chain resolved for this codepoint (primary or a
      --  fallback). All metrics below derive from this font.
      Selected : Textrender.Fonts.Font;

      Pack_X  : Natural;
      Pack_Y  : Natural;
      Atlas_X : Natural;
      Atlas_Y : Natural;

      Scale : Float;

      Glyph_W : Positive;
      Glyph_H : Positive;

      Raw_W : Float;
      Raw_H : Float;

      Return_Status : Status_Code;
   begin
      if not Textrender.Fonts.Loaded (R.State.Font) then
         return Font_Not_Loaded;
      end if;

      declare
         Cached_Cursor : constant Glyph_Caches.Cursor := Cache_Find (C);
      begin
         if Glyph_Caches.Has_Element (Cached_Cursor) then
            declare
               Cached : constant Cached_Glyph := Glyph_Caches.Element (Cached_Cursor);
            begin
               M := Cached.Metric;
               return Cached.Status;
            end;
         end if;
      end;

      --  Per-glyph font fallback: consult the primary font first, then each
      --  appended fallback in order, and resolve C to the first font that
      --  directly maps it. Has_Glyph is a cmap lookup only -- it never
      --  rasterizes, so probing the chain is cheap. When no font in the chain
      --  maps C, keep the primary font so its own Lookup_Glyph emits the
      --  not-found path (Glyph_Used_Fallback -> Glyph_Missing), matching a
      --  single-font renderer exactly. Resolution is deterministic for a given
      --  codepoint and fixed chain order, so the per-codepoint cache key stays
      --  correct: C always resolves through the same font.
      Selected := R.State.Font;

      --  Skip a font that maps the codepoint but cannot draw it. Has_Glyph is a
      --  character-map lookup, and mapping is not the same as being able to
      --  render: a colour font is all bitmaps and has no outlines at all, so
      --  selecting one here would commit to it and then fail, because the loop
      --  below exits on the first match and never reconsiders. Noto Color Emoji
      --  maps a good deal more than emoji -- stars, arrows, ticks that the text
      --  fallbacks also carry -- so without this, adding it to the chain would
      --  make those characters disappear instead of drawing from DejaVu.
      if not Textrender.Fonts.Has_Glyph (R.State.Font, C) then
         for F of R.State.Fallbacks loop
            if Textrender.Fonts.Has_Glyph (F, C)
              and then not Textrender.Fonts.Is_Bitmap_Only (F)
            then
               Selected := F;
               exit;
            end if;
         end loop;
      end if;

      Scale :=
        Float (R.State.Pixel_Size)
        / Float (Textrender.Fonts.Units_Per_Em (Selected));

      Lookup_Result :=
        Textrender.Fonts.Lookup_Glyph (Selected, C, G);

      if Lookup_Result = Textrender.Fonts.Glyph_Not_Found then
         return Glyph_Missing;
      end if;

      --  Empty glyph (space etc.)
      if G.Is_Empty then
         M.X := 0;
         M.Y := 0;
         M.W := 0;
         M.H := 0;

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

         Cache_Insert (C, (Status => Return_Status, Metric => M));

         return Return_Status;
      end if;

      --  Use the font's ascent/descent (not the per-glyph bbox) for vertical
      --  atlas extent. This makes the atlas top correspond to the same
      --  baseline-relative position for every glyph, so all glyphs share an
      --  identical Bearing_Y and snap to the same screen row. Any boundary
      --  effect from per-glyph Y_Max — the cause of "r jitters" — disappears.
      declare
         Font_Ascent  : constant Integer := Textrender.Fonts.Ascent (Selected);
         Font_Descent : constant Integer := Textrender.Fonts.Descent (Selected);
         Line_Top     : constant Integer := Integer'Max (Font_Ascent, G.Bounds.Y_Max);
         Line_Bottom  : constant Integer := Integer'Min (Font_Descent, G.Bounds.Y_Min);
         Slant        : constant Float   := Slant_For (Style);
         --  For italic, the slanted glyph extends to the right at the top and
         --  to the left at the bottom (descender). Extend the atlas
         --  horizontally to capture both ends. X_Slant_Min is in font units
         --  and is <= 0; X_Slant_Max is >= 0.
         X_Slant_Min  : constant Integer :=
           (if Slant > 0.0 and then Line_Bottom < 0
            then Integer (Float (Line_Bottom) * Slant - 0.999)
            else 0);
         X_Slant_Max  : constant Integer :=
           (if Slant > 0.0 and then Line_Top > 0
            then Integer (Float (Line_Top) * Slant + 0.999)
            else 0);
         X_Min_Adj    : constant Integer := G.Bounds.X_Min + X_Slant_Min;
         X_Max_Adj    : constant Integer := G.Bounds.X_Max + X_Slant_Max;
      begin
         Raw_W := Float (X_Max_Adj - X_Min_Adj) * Scale;
         Raw_H := Float (Line_Top - Line_Bottom) * Scale;

         Glyph_W :=
           (if Raw_W <= 0.0 then 1
            else Positive (Integer (Raw_W + 0.999)));

         Glyph_H :=
           (if Raw_H <= 0.0 then 1
            else Positive (Integer (Raw_H + 0.999)));

         if not Textrender.Atlases.Allocate_Rect
           (R.State.Atlas,
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
           (F           => Selected,
            A           => R.State.Atlas,
            Glyph_Index => G.Glyph_Index,
            Atlas_X     => Atlas_X,
            Atlas_Y     => Atlas_Y,
            Glyph_W     => Glyph_W,
            Glyph_H     => Glyph_H,
            X_Min       => X_Min_Adj,
            Y_Min       => Line_Bottom,
            X_Max       => X_Max_Adj,
            Y_Max       => Line_Top,
            Pixel_Size  => R.State.Pixel_Size,
            Transform   =>
              (XX => 1.0, XY => Slant, YX => 0.0, YY => 1.0, DX => 0.0, DY => 0.0))
         then
            M := (X         => 0,
                  Y         => 0,
                  W         => 0,
                  H         => 0,
                  U0        => 0.0,
                  V0        => 0.0,
                  U1        => 0.0,
                  V1        => 0.0,
                  Advance_X => Float (G.Advance_X) * Scale,
                  Bearing_X => Float (G.Left_Side_Bearing) * Scale,
                  Bearing_Y => 0.0);

            Cache_Insert (C, (Status => Rasterize_Failed, Metric => M));

            return Rasterize_Failed;
         end if;

         M.X := Atlas_X;
         M.Y := Atlas_Y;
         M.W := Glyph_W;
         M.H := Glyph_H;

         --  Derive the atlas UV rectangle from the very same integer pixel
         --  rectangle (M.X/M.Y/M.W/M.H) the caller draws. The sampled span is
         --  then guaranteed to equal the drawn quad size to the texel, so a
         --  glyph can never read a neighbour's texels or leave a phantom gap.
         --  (Deriving U1 from an independently-rounded width was the class of
         --  mistake that produces per-glyph spacing glitches.)
         declare
            Atlas_W : constant Float :=
              Float (Textrender.Atlases.Width (R.State.Atlas));
            Atlas_H : constant Float :=
              Float (Textrender.Atlases.Height (R.State.Atlas));
         begin
            M.U0 := Float (M.X) / Atlas_W;
            M.V0 := Float (M.Y) / Atlas_H;
            M.U1 := Float (M.X + M.W) / Atlas_W;
            M.V1 := Float (M.Y + M.H) / Atlas_H;
         end;

         M.Advance_X :=
           Float (G.Advance_X) * Scale;

         --  For italic the leftmost extent moves to X_Slant_Min font units
         --  (<= 0) past the original LSB to capture the descender slant.
         M.Bearing_X :=
           Float (G.Left_Side_Bearing + X_Slant_Min) * Scale;

         --  Uniform across all glyphs (driven by font ascent, not per-glyph
         --  Y_Max). This guarantees every atlas top lands at the same screen
         --  row, so no glyph ever jitters relative to its row-mates.
         M.Bearing_Y := Float'Floor (Float (Line_Top) * Scale);
      end;

      pragma Assert (M.Advance_X >= 0.0);
      pragma Assert (M.U0 <= M.U1);
      pragma Assert (M.V0 <= M.V1);

      Return_Status :=
        (if Lookup_Result = Textrender.Fonts.Glyph_Used_Fallback
         then Glyph_Missing
         else Success);

      Cache_Insert (C, (Status => Return_Status, Metric => M));

      R.State.Atlas_Dirty_V := True;

      return Return_Status;
   end Get_Glyph;

   function Get_Glyph_By_Index
     (R           : in out Renderer;
      Glyph_Index : Natural;
      M           : out Glyph_Metric;
      Font_Index  : Natural := 0;
      Style       : Font_Style := Regular) return Status_Code
   is
      Key : constant Glyph_Index_Key :=
        (Font_Index => Font_Index, Glyph_Index => Glyph_Index);

      procedure Cache_Insert (Item : Cached_Glyph) is
      begin
         case Style is
            when Regular => R.State.Glyph_Index_Cache.Insert (Key, Item);
            when Italic  => R.State.Italic_Glyph_Index_Cache.Insert (Key, Item);
         end case;
      end Cache_Insert;

      function Cache_Find return Glyph_Index_Caches.Cursor is
        (case Style is
           when Regular => R.State.Glyph_Index_Cache.Find (Key),
           when Italic  => R.State.Italic_Glyph_Index_Cache.Find (Key));

      Selected : Textrender.Fonts.Font;
      G       : Textrender.Fonts.Glyph_Info;
      Pack_X  : Natural;
      Pack_Y  : Natural;
      Atlas_X : Natural;
      Atlas_Y : Natural;
      Scale   : Float;
      Glyph_W : Positive;
      Glyph_H : Positive;
      Raw_W   : Float;
      Raw_H   : Float;
   begin
      if not Textrender.Fonts.Loaded (R.State.Font) then
         return Font_Not_Loaded;
      end if;

      if Font_Index = 0 then
         Selected := R.State.Font;
      elsif Font_Index <= Natural (R.State.Fallbacks.Length) then
         Selected := R.State.Fallbacks.Element (Positive (Font_Index));
      else
         return Glyph_Missing;
      end if;

      declare
         Cached_Cursor : constant Glyph_Index_Caches.Cursor := Cache_Find;
      begin
         if Glyph_Index_Caches.Has_Element (Cached_Cursor) then
            declare
               Cached : constant Cached_Glyph := Glyph_Index_Caches.Element (Cached_Cursor);
            begin
               M := Cached.Metric;
               return Cached.Status;
            end;
         end if;
      end;

      if Textrender.Fonts.Lookup_Glyph_By_Index
        (Selected, Glyph_Index, G) /= Textrender.Fonts.Glyph_Found
      then
         return Glyph_Missing;
      end if;

      Scale :=
        Float (R.State.Pixel_Size)
        / Float (Textrender.Fonts.Units_Per_Em (Selected));

      if G.Is_Empty then
         M.X := 0;
         M.Y := 0;
         M.W := 0;
         M.H := 0;
         M.U0 := 0.0;
         M.V0 := 0.0;
         M.U1 := 0.0;
         M.V1 := 0.0;
         M.Advance_X := Float (G.Advance_X) * Scale;
         M.Bearing_X := Float (G.Left_Side_Bearing) * Scale;
         M.Bearing_Y := 0.0;
         Cache_Insert ((Status => Success, Metric => M));
         return Success;
      end if;

      declare
         Font_Ascent  : constant Integer :=
           Textrender.Fonts.Ascent (Selected);
         Font_Descent : constant Integer :=
           Textrender.Fonts.Descent (Selected);
         Line_Top     : constant Integer :=
           Integer'Max (Font_Ascent, G.Bounds.Y_Max);
         Line_Bottom  : constant Integer :=
           Integer'Min (Font_Descent, G.Bounds.Y_Min);
         Slant        : constant Float := Slant_For (Style);
         X_Slant_Min  : constant Integer :=
           (if Slant > 0.0 and then Line_Bottom < 0
            then Integer (Float (Line_Bottom) * Slant - 0.999)
            else 0);
         X_Slant_Max  : constant Integer :=
           (if Slant > 0.0 and then Line_Top > 0
            then Integer (Float (Line_Top) * Slant + 0.999)
            else 0);
         X_Min_Adj    : constant Integer := G.Bounds.X_Min + X_Slant_Min;
         X_Max_Adj    : constant Integer := G.Bounds.X_Max + X_Slant_Max;
      begin
         Raw_W := Float (X_Max_Adj - X_Min_Adj) * Scale;
         Raw_H := Float (Line_Top - Line_Bottom) * Scale;

         Glyph_W :=
           (if Raw_W <= 0.0 then 1
            else Positive (Integer (Raw_W + 0.999)));
         Glyph_H :=
           (if Raw_H <= 0.0 then 1
            else Positive (Integer (Raw_H + 0.999)));

         if not Textrender.Atlases.Allocate_Rect
           (R.State.Atlas,
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
           (F           => Selected,
            A           => R.State.Atlas,
            Glyph_Index => G.Glyph_Index,
            Atlas_X     => Atlas_X,
            Atlas_Y     => Atlas_Y,
            Glyph_W     => Glyph_W,
            Glyph_H     => Glyph_H,
            X_Min       => X_Min_Adj,
            Y_Min       => Line_Bottom,
            X_Max       => X_Max_Adj,
            Y_Max       => Line_Top,
            Pixel_Size  => R.State.Pixel_Size,
            Transform   =>
              (XX => 1.0,
               XY => Slant,
               YX => 0.0,
               YY => 1.0,
               DX => 0.0,
               DY => 0.0))
         then
            M := (X         => 0,
                  Y         => 0,
                  W         => 0,
                  H         => 0,
                  U0        => 0.0,
                  V0        => 0.0,
                  U1        => 0.0,
                  V1        => 0.0,
                  Advance_X => Float (G.Advance_X) * Scale,
                  Bearing_X => Float (G.Left_Side_Bearing) * Scale,
                  Bearing_Y => 0.0);
            Cache_Insert ((Status => Rasterize_Failed, Metric => M));
            return Rasterize_Failed;
         end if;

         M.X := Atlas_X;
         M.Y := Atlas_Y;
         M.W := Glyph_W;
         M.H := Glyph_H;

         declare
            Atlas_W : constant Float :=
              Float (Textrender.Atlases.Width (R.State.Atlas));
            Atlas_H : constant Float :=
              Float (Textrender.Atlases.Height (R.State.Atlas));
         begin
            M.U0 := Float (M.X) / Atlas_W;
            M.V0 := Float (M.Y) / Atlas_H;
            M.U1 := Float (M.X + M.W) / Atlas_W;
            M.V1 := Float (M.Y + M.H) / Atlas_H;
         end;

         M.Advance_X := Float (G.Advance_X) * Scale;
         M.Bearing_X := Float (G.Left_Side_Bearing + X_Slant_Min) * Scale;
         M.Bearing_Y := Float'Floor (Float (Line_Top) * Scale);
      end;

      pragma Assert (M.Advance_X >= 0.0);
      pragma Assert (M.U0 <= M.U1);
      pragma Assert (M.V0 <= M.V1);

      Cache_Insert ((Status => Success, Metric => M));
      R.State.Atlas_Dirty_V := True;

      return Success;
   end Get_Glyph_By_Index;

   function Place_Glyph_In_Cell
     (R      : Renderer;
      M      : Glyph_Metric;
      Cell_X : Float;
      Cell_Y : Float) return Glyph_Placement
   is
      Baseline_Y : constant Float := Cell_Y + Ascent (R);
   begin
      return
        (X => Cell_X + M.Bearing_X,
         Y => Baseline_Y - M.Bearing_Y);
   end Place_Glyph_In_Cell;

   -----------------------------
   --  Atlas Access
   -----------------------------

   function Atlas_Width (R : Renderer) return Positive is
   begin
      return Textrender.Atlases.Width (R.State.Atlas);
   end Atlas_Width;

   function Atlas_Height (R : Renderer) return Positive is
   begin
      return Textrender.Atlases.Height (R.State.Atlas);
   end Atlas_Height;

   function Atlas_Pixels
     (R : Renderer) return access constant Alpha_Buffer
   is
   begin
      return Textrender.Atlases.Pixels (R.State.Atlas);
   end Atlas_Pixels;

   function Atlas_Dirty (R : Renderer) return Boolean is
   begin
      return R.State.Atlas_Dirty_V;
   end Atlas_Dirty;

   procedure Clear_Atlas_Dirty (R : in out Renderer) is
   begin
      R.State.Atlas_Dirty_V := False;
   end Clear_Atlas_Dirty;

   -----------------------------
   --  Preload
   -----------------------------

   function Preload
     (R     : in out Renderer;
      First : Codepoint;
      Last  : Codepoint) return Status_Code
   is
      Discard : Glyph_Metric;
      Status  : Status_Code;
   begin
      if not Textrender.Fonts.Loaded (R.State.Font) then
         return Font_Not_Loaded;
      end if;

      if Last < First then
         return Success;
      end if;

      for C in First .. Last loop
         Status := Get_Glyph (R, C, Discard);

         if Status = Atlas_Full then
            return Atlas_Full;
         end if;
      end loop;

      return Success;
   end Preload;

   procedure Set_Image_Decoder
     (R      : in out Renderer;
      Extent : Image_Extent_Reader;
      Decode : Image_Decoder) is
   begin
      Ensure_State (R);
      R.State.Extent_Reader := Extent;
      R.State.Decoder := Decode;
   end Set_Image_Decoder;

   --  The font in the chain that has a colour picture for this codepoint, and the
   --  glyph index within it. Searched in the same order as outlines: primary
   --  first, then each fallback.
   --  Which font matched: 0 for the primary, else the fallback's position.
   procedure Find_Colour_Source
     (R           : Renderer;
      C           : Codepoint;
      Found       : out Boolean;
      Bitmap      : out Textrender.Fonts.Colour_Bitmap;
      Source_Index : out Natural)
   is
      procedure Try (F : Textrender.Fonts.Font; Which : Natural) is
         Index : Natural := 0;
      begin
         if Found or else not Textrender.Fonts.Has_Colour_Bitmaps (F) then
            return;
         end if;

         --  The character map alone: Lookup_Glyph reads bounds out of glyf to
         --  fill its metrics, and a colour font has no glyf.
         if not Textrender.Fonts.Glyph_Index_Of (F, C, Index) then
            return;
         end if;

         declare
            B : constant Textrender.Fonts.Colour_Bitmap :=
              Textrender.Fonts.Colour_Bitmap_For (F, Index, R.State.Pixel_Size);
         begin
            if B.Format /= Textrender.Fonts.No_Colour_Image then
               Found := True;
               Bitmap := B;
               Source_Index := Which;
            end if;
         end;
      end Try;
   begin
      Found := False;
      Bitmap := (Format => Textrender.Fonts.No_Colour_Image, others => <>);
      Source_Index := 0;

      if R.State = null then
         return;
      end if;

      Try (R.State.Font, 0);

      declare
         Which : Natural := 0;
      begin
         for F of R.State.Fallbacks loop
            exit when Found;
            Which := Which + 1;
            Try (F, Which);
         end loop;
      end;
   end Find_Colour_Source;

   --  The font in the chain that builds this codepoint out of layers, if any.
   --  Searched like the picture formats: primary first, then each fallback.
   procedure Find_Layer_Source
     (R            : Renderer;
      C            : Codepoint;
      Found        : out Boolean;
      Glyph_Index  : out Natural;
      Source_Index : out Natural);

   function Has_Colour_Glyph (R : Renderer; C : Codepoint) return Boolean is
      Found  : Boolean;
      Bitmap : Textrender.Fonts.Colour_Bitmap;
      Source : Natural;
      Glyph  : Natural;
   begin
      if R.State = null then
         return False;
      end if;

      --  Layered glyphs come first because they need nothing installed: they are
      --  outlines and a palette, both of which this crate can already read. The
      --  picture formats need the caller's decoder, so they are only offered
      --  once there is one.
      Find_Layer_Source (R, C, Found, Glyph, Source);

      if Found then
         return True;
      end if;

      if R.State.Extent_Reader = null or else R.State.Decoder = null then
         return False;
      end if;

      Find_Colour_Source (R, C, Found, Bitmap, Source);
      return Found;
   end Has_Colour_Glyph;

   procedure Find_Layer_Source
     (R            : Renderer;
      C            : Codepoint;
      Found        : out Boolean;
      Glyph_Index  : out Natural;
      Source_Index : out Natural)
   is
      procedure Try (F : Textrender.Fonts.Font; Which : Natural) is
         Index : Natural := 0;
      begin
         if Found
           or else not (Textrender.Fonts.Has_Colour_Layers (F)
                        or else Textrender.Fonts.Has_Colour_Paints (F))
         then
            return;
         end if;

         if not Textrender.Fonts.Glyph_Index_Of (F, C, Index) then
            return;
         end if;

         if Textrender.Fonts.Colour_Layer_Count (F, Index) > 0
           or else Textrender.Fonts.Has_Paint_Graph (F, Index)
         then
            Found := True;
            Glyph_Index := Index;
            Source_Index := Which;
         end if;
      end Try;
   begin
      Found := False;
      Glyph_Index := 0;
      Source_Index := 0;

      if R.State = null then
         return;
      end if;

      Try (R.State.Font, 0);

      declare
         Which : Natural := 0;
      begin
         for F of R.State.Fallbacks loop
            exit when Found;
            Which := Which + 1;
            Try (F, Which);
         end loop;
      end;
   end Find_Layer_Source;

   --  Draw a layered colour glyph into its own tile.
   --
   --  Each layer is an ordinary outline, so the existing rasterizer draws it;
   --  what this adds is doing that once per layer into a scratch coverage
   --  buffer, tinting by the layer's palette colour, and compositing the results
   --  in order. No decoder is involved -- there is no picture to decode.
   --
   --  Every layer is rasterized against the union of all their bounds, so they
   --  share one coordinate space and line up as the font intended.
   function Build_Layered_Tile
     (R     : in out Renderer;
      Font  : Textrender.Fonts.Font;
      Glyph : Natural;
      Tile  : out Rgba_Buffer_Access;
      G     : out Colour_Glyph)
      return Boolean
   is
      V0_Count : constant Natural := Textrender.Fonts.Colour_Layer_Count (Font, Glyph);

      Draws     : Textrender.Fonts.Colour_Draw_Array;
      Draw_Count : Natural := 0;
      Layered   : constant Boolean :=
        Textrender.Fonts.Colour_Draws_For (Font, Glyph, Draws, Draw_Count);

      Count : constant Natural := (if Layered then Draw_Count else V0_Count);

      --  The colour a fill gives at a point, in font units before the draw's
      --  transform. A solid answers the same everywhere; a gradient is evaluated
      --  where the pixel falls.
      procedure Fill_At
        (Fill : Textrender.Fonts.Paint_Fill;
         X, Y : Float;
         Red, Green, Blue, Opacity : out Natural);

      procedure Fill_At
        (Fill : Textrender.Fonts.Paint_Fill;
         X, Y : Float;
         Red, Green, Blue, Opacity : out Natural)
      is
         T : Float := 0.0;
      begin
         Red := Fill.Red;
         Green := Fill.Green;
         Blue := Fill.Blue;
         Opacity := Fill.Alpha;

         if Fill.Kind = Textrender.Fonts.Solid_Fill or else Fill.Stop_Count = 0 then
            return;
         end if;

         if Fill.Kind = Textrender.Fonts.Linear_Gradient then
            --  Distance along p0->p1, which is what the stop offsets index.
            declare
               DX_L : constant Float := Fill.X1 - Fill.X0;
               DY_L : constant Float := Fill.Y1 - Fill.Y0;
               Len2 : constant Float := DX_L * DX_L + DY_L * DY_L;
            begin
               if Len2 <= 0.0 then
                  T := 0.0;
               else
                  T := ((X - Fill.X0) * DX_L + (Y - Fill.Y0) * DY_L) / Len2;
               end if;
            end;
         else
            --  Radial, approximated by distance from the outer circle's centre
            --  between the two radii. The two-circle form this format allows is
            --  rare and its cone is not built here.
            declare
               DX_R : constant Float := X - Fill.X1;
               DY_R : constant Float := Y - Fill.Y1;
               Dist : constant Float := Sqrt (DX_R * DX_R + DY_R * DY_R);
               Span : constant Float := Fill.Radius_1 - Fill.Radius_0;
            begin
               if Span <= 0.0 then
                  T := 0.0;
               else
                  T := (Dist - Fill.Radius_0) / Span;
               end if;
            end;
         end if;

         --  Pad: the end stops carry on outside the line.
         T := Float'Max (0.0, Float'Min (1.0, T));

         declare
            Lower : Natural := 1;
            Upper : Natural := Fill.Stop_Count;
         begin
            for Index in 1 .. Fill.Stop_Count loop
               if Fill.Stops (Index).Position <= T then
                  Lower := Index;
               end if;
            end loop;

            Upper := Natural'Min (Fill.Stop_Count, Lower + 1);

            declare
               A : constant Textrender.Fonts.Colour_Stop := Fill.Stops (Lower);
               B : constant Textrender.Fonts.Colour_Stop := Fill.Stops (Upper);
               Span : constant Float := B.Position - A.Position;
               F    : constant Float :=
                 (if Span <= 0.0 then 0.0
                  else Float'Max (0.0, Float'Min (1.0, (T - A.Position) / Span)));
            begin
               Red := A.Red + Natural (Float (B.Red - A.Red) * F);
               Green := A.Green + Natural (Float (B.Green - A.Green) * F);
               Blue := A.Blue + Natural (Float (B.Blue - A.Blue) * F);
               Opacity := A.Alpha + Natural (Float (B.Alpha - A.Alpha) * F);
            end;
         end;
      exception
         when others =>
            null;
      end Fill_At;

      X_Min, Y_Min, X_Max, Y_Max : Integer := 0;
      Have_Bounds : Boolean := False;

      --  Which outline each layer draws, whichever version said so.
      function Layer_Glyph (Index : Natural) return Natural is
        (if Layered
         then Draws (Index + 1).Glyph_Index
         else Textrender.Fonts.Colour_Layer_At (Font, Glyph, Index).Glyph_Index);
   begin
      Tile := null;
      G := (Width => 0, Height => 0, Advance_X => 0.0, Bearing_Y => 0.0, others => <>);

      if Count = 0 then
         return False;
      end if;

      --  The union of the layers' bounds. A layer with no outline contributes
      --  nothing and is skipped.
      for Index in 0 .. Count - 1 loop
         declare
            Info : Textrender.Fonts.Glyph_Info;
         begin
            if Textrender.Fonts.Lookup_Glyph_By_Index (Font, Layer_Glyph (Index), Info)
                 = Textrender.Fonts.Glyph_Found
              and then not Info.Is_Empty
            then
               if not Have_Bounds then
                  X_Min := Info.Bounds.X_Min;
                  Y_Min := Info.Bounds.Y_Min;
                  X_Max := Info.Bounds.X_Max;
                  Y_Max := Info.Bounds.Y_Max;
                  Have_Bounds := True;
               else
                  X_Min := Integer'Min (X_Min, Info.Bounds.X_Min);
                  Y_Min := Integer'Min (Y_Min, Info.Bounds.Y_Min);
                  X_Max := Integer'Max (X_Max, Info.Bounds.X_Max);
                  Y_Max := Integer'Max (Y_Max, Info.Bounds.Y_Max);
               end if;
            end if;
         end;
      end loop;

      if not Have_Bounds or else X_Max <= X_Min or else Y_Max <= Y_Min then
         return False;
      end if;

      declare
         Box_W : constant Positive := Positive'Max (1, R.State.Cell_Width_V * 2);
         Box_H : constant Positive := Positive'Max (1, R.State.Cell_Height_V);
         Units : constant Float := Float (Textrender.Fonts.Units_Per_Em (Font));
         Span_W : constant Float := Float (X_Max - X_Min);
         Span_H : constant Float := Float (Y_Max - Y_Min);
         Fit    : constant Float :=
           Float'Min (Float (Box_W) / Span_W, Float (Box_H) / Span_H);
         Dst_W  : constant Positive :=
           Positive'Max (1, Natural (Float'Floor (Span_W * Fit)));
         Dst_H  : constant Positive :=
           Positive'Max (1, Natural (Float'Floor (Span_H * Fit)));
         Raster_Size : constant Positive :=
           Positive'Max (1, Natural (Float'Floor (Units * Fit)));

         Scratch : Textrender.Atlases.Atlas;
         Pack_X, Pack_Y : Natural;
      begin
         Textrender.Atlases.Init (Scratch, Dst_W, Dst_H);
         Tile := new Rgba_Buffer (0 .. Dst_W * Dst_H * 4 - 1);
         Tile.all := [others => 0];

         for Index in 0 .. Count - 1 loop
            declare
               Draw : constant Textrender.Fonts.Colour_Draw :=
                 (if Layered then Draws (Index + 1) else Textrender.Fonts.Colour_Draw'(others => <>));
               V0 : constant Textrender.Fonts.Colour_Layer :=
                 (if Layered
                  then Textrender.Fonts.Colour_Layer'(others => <>)
                  else Textrender.Fonts.Colour_Layer_At (Font, Glyph, Index));
               This_Glyph : constant Natural :=
                 (if Layered then Draw.Glyph_Index else V0.Glyph_Index);
            begin
               Textrender.Atlases.Clear (Scratch);

               if Textrender.Atlases.Allocate_Rect (Scratch, Dst_W, Dst_H, Pack_X, Pack_Y)
                 and then Textrender.Rasterizer.Rasterize_Glyph
                   (F           => Font,
                    A           => Scratch,
                    Glyph_Index => This_Glyph,
                    Atlas_X     => 0,
                    Atlas_Y     => 0,
                    Glyph_W     => Dst_W,
                    Glyph_H     => Dst_H,
                    X_Min       => X_Min,
                    Y_Min       => Y_Min,
                    X_Max       => X_Max,
                    Y_Max       => Y_Max,
                    Pixel_Size  => Raster_Size,
                    Transform   =>
                      (if Layered
                       then (XX => Draw.XX, XY => Draw.XY, YX => Draw.YX,
                             YY => Draw.YY, DX => Draw.DX, DY => Draw.DY)
                       else Textrender.Rasterizer.Identity_Transform))
               then
                  declare
                     Cover : constant access constant Alpha_Buffer :=
                       Textrender.Atlases.Pixels (Scratch);
                  begin
                     if Cover /= null then
                        for Row in 0 .. Dst_H - 1 loop
                           for Col in 0 .. Dst_W - 1 loop
                              declare
                                 At_Cover : constant Natural :=
                                   Row * Textrender.Atlases.Width (Scratch) + Col;
                                 At_Dst : constant Natural := (Row * Dst_W + Col) * 4;

                                 --  Where this pixel falls in font units, which
                                 --  is the space a gradient is described in.
                                 Unit_X : constant Float :=
                                   Float (X_Min) + (Float (Col) + 0.5) * Span_W / Float (Dst_W);
                                 Unit_Y : constant Float :=
                                   Float (Y_Max) - (Float (Row) + 0.5) * Span_H / Float (Dst_H);

                                 Src_R, Src_G, Src_B, Src_A : Natural;
                              begin
                                 exit when At_Cover > Cover'Last;

                                 if Layered then
                                    Fill_At (Draw.Fill, Unit_X, Unit_Y,
                                             Src_R, Src_G, Src_B, Src_A);
                                 else
                                    Src_R := V0.Red;
                                    Src_G := V0.Green;
                                    Src_B := V0.Blue;
                                    Src_A := V0.Alpha;
                                 end if;

                                 Src_A := Natural (Cover (At_Cover)) * Src_A / 255;

                                 if Src_A > 0 then
                                    for Channel in 0 .. 2 loop
                                       declare
                                          Colour : constant Natural :=
                                            (case Channel is
                                               when 0 => Src_R,
                                               when 1 => Src_G,
                                               when others => Src_B);
                                          Under : constant Natural :=
                                            Natural (Tile (At_Dst + Channel));
                                       begin
                                          Tile (At_Dst + Channel) :=
                                            Alpha ((Colour * Src_A + Under * (255 - Src_A)) / 255);
                                       end;
                                    end loop;

                                    declare
                                       Under : constant Natural := Natural (Tile (At_Dst + 3));
                                    begin
                                       Tile (At_Dst + 3) :=
                                         Alpha (Src_A + Under * (255 - Src_A) / 255);
                                    end;
                                 end if;
                              end;
                           end loop;
                        end loop;
                     end if;
                  end;
               end if;
            end;
         end loop;

         Textrender.Atlases.Reset (Scratch);

         G :=
           (Width => Dst_W, Height => Dst_H,
            Advance_X => Float (Box_W),
            Bearing_Y => Ascent (R) - Float ((R.State.Cell_Height_V - Dst_H) / 2),
            others => <>);
         return True;
      end;
   exception
      when others =>
         return False;
   end Build_Layered_Tile;

   Colour_Sheet_Side : constant := 512;

   --  Find room for a picture in the sheet and note where it went.
   --
   --  Shelf packing: a run left to right, wrapping to a new shelf as tall as the
   --  tallest tile on the last one. Emoji are all about a line tall, so the waste
   --  is slight and the alternative -- a real packer -- would be more code than
   --  the problem deserves.
   procedure Place_In_Colour_Sheet
     (R      : in out Renderer;
      Width  : Positive;
      Height : Positive;
      X      : out Natural;
      Y      : out Natural;
      Placed : out Boolean);

   procedure Place_In_Colour_Sheet
     (R      : in out Renderer;
      Width  : Positive;
      Height : Positive;
      X      : out Natural;
      Y      : out Natural;
      Placed : out Boolean) is
   begin
      X := 0;
      Y := 0;
      Placed := False;

      if Width > Colour_Sheet_Side then
         return;
      end if;

      if R.State.Colour_Sheet = null then
         R.State.Colour_Sheet :=
           new Rgba_Buffer (0 .. Colour_Sheet_Side * Colour_Sheet_Side * 4 - 1);
         R.State.Colour_Sheet.all := [others => 0];
         R.State.Colour_Width := Colour_Sheet_Side;
         R.State.Colour_Height := Colour_Sheet_Side;
      end if;

      if R.State.Colour_Pen_X + Width > Colour_Sheet_Side then
         R.State.Colour_Pen_X := 0;
         R.State.Colour_Pen_Y := R.State.Colour_Pen_Y + R.State.Colour_Shelf;
         R.State.Colour_Shelf := 0;
      end if;

      if R.State.Colour_Pen_Y + Height > Colour_Sheet_Side then
         return;
      end if;

      X := R.State.Colour_Pen_X;
      Y := R.State.Colour_Pen_Y;
      R.State.Colour_Pen_X := R.State.Colour_Pen_X + Width;
      R.State.Colour_Shelf := Natural'Max (R.State.Colour_Shelf, Height);
      Placed := True;
   end Place_In_Colour_Sheet;

   --  Copy a freshly built tile into the sheet, record where it went, and let the
   --  tile go. Both routes to a colour glyph -- a decoded picture and composited
   --  layers -- end here.
   function Commit_Colour_Tile
     (R    : in out Renderer;
      C    : Codepoint;
      Tile : in out Rgba_Buffer_Access;
      G    : in out Colour_Glyph)
      return Boolean
   is
      X, Y   : Natural;
      Placed : Boolean;
   begin
      if Tile = null or else G.Width = 0 or else G.Height = 0 then
         Free_Rgba (Tile);
         Tile := null;
         return False;
      end if;

      Place_In_Colour_Sheet (R, G.Width, G.Height, X, Y, Placed);

      if not Placed then
         Free_Rgba (Tile);
         Tile := null;
         return False;
      end if;

      for Row in 0 .. G.Height - 1 loop
         for Column in 0 .. G.Width - 1 loop
            declare
               From : constant Natural := (Row * G.Width + Column) * 4;
               Into : constant Natural :=
                 ((Y + Row) * R.State.Colour_Width + X + Column) * 4;
            begin
               if From + 3 <= Tile'Last
                 and then Into + 3 <= R.State.Colour_Sheet'Last
               then
                  for Channel in 0 .. 3 loop
                     R.State.Colour_Sheet (Into + Channel) := Tile (From + Channel);
                  end loop;
               end if;
            end;
         end loop;
      end loop;

      Free_Rgba (Tile);
      Tile := null;

      G.X := X;
      G.Y := Y;
      G.U0 := Float (X) / Float (R.State.Colour_Width);
      G.V0 := Float (Y) / Float (R.State.Colour_Height);
      G.U1 := Float (X + G.Width) / Float (R.State.Colour_Width);
      G.V1 := Float (Y + G.Height) / Float (R.State.Colour_Height);

      R.State.Colour_Dirty_V := True;
      R.State.Colour_Cache.Insert (C, G);
      return True;
   end Commit_Colour_Tile;

   function Get_Colour_Glyph
     (R : in out Renderer;
      C : Codepoint;
      G : out Colour_Glyph)
      return Status_Code
   is
      Found  : Boolean;
      Bitmap : Textrender.Fonts.Colour_Bitmap;
      Source : Natural;
   begin
      G := (Width => 0, Height => 0, Advance_X => 0.0, Bearing_Y => 0.0, others => <>);

      if R.State = null or else not R.State.Font.Loaded then
         return Font_Not_Loaded;
      end if;

      if R.State.Colour_Cache.Contains (C) then
         G := R.State.Colour_Cache.Element (C);
         return Success;
      end if;

      --  A layered glyph is drawn rather than decoded, so it is tried before the
      --  decoder is required at all.
      declare
         Layered : Boolean;
         Layer_Glyph : Natural;
         Layer_Source : Natural;
      begin
         Find_Layer_Source (R, C, Layered, Layer_Glyph, Layer_Source);

         if Layered then
            declare
               Tile : Rgba_Buffer_Access;
            begin
               if Build_Layered_Tile
                    (R,
                     (if Layer_Source = 0
                      then R.State.Font
                      else R.State.Fallbacks (Layer_Source)),
                     Layer_Glyph, Tile, G)
                 and then Commit_Colour_Tile (R, C, Tile, G)
               then
                  return Success;
               end if;
            end;
         end if;
      end;

      if R.State.Extent_Reader = null or else R.State.Decoder = null then
         return Glyph_Missing;
      end if;

      Find_Colour_Source (R, C, Found, Bitmap, Source);

      if not Found then
         return Glyph_Missing;
      end if;

      declare
         --  The picture, as the font stores it.
         Data : Encoded_Image (0 .. Bitmap.Data_Length - 1);
         Src_W : Natural := 0;
         Src_H : Natural := 0;
      begin
         for I in Data'Range loop
            Data (I) :=
              Alpha (Textrender.Fonts.Byte_At
                       ((if Source = 0
                         then R.State.Font
                         else R.State.Fallbacks (Source)),
                        Bitmap.Data_Offset + I));
         end loop;

         if not R.State.Extent_Reader (Data, Src_W, Src_H)
           or else Src_W = 0 or else Src_H = 0
         then
            return Glyph_Missing;
         end if;

         declare
            Src : Rgba_Buffer (0 .. Src_W * Src_H * 4 - 1) := [others => 0];
         begin
            if not R.State.Decoder (Data, Src_W, Src_H, Src) then
               return Glyph_Missing;
            end if;

            --  Fit the picture into two cells by its own aspect ratio: emoji are
            --  square and occupy two cells of a monospaced grid.
            declare
               Box_W : constant Positive := Positive'Max (1, R.State.Cell_Width_V * 2);
               Box_H : constant Positive := Positive'Max (1, R.State.Cell_Height_V);
               Scale : constant Float :=
                 Float'Min (Float (Box_W) / Float (Src_W), Float (Box_H) / Float (Src_H));
               Dst_W : constant Positive :=
                 Positive'Max (1, Natural (Float'Floor (Float (Src_W) * Scale)));
               Dst_H : constant Positive :=
                 Positive'Max (1, Natural (Float'Floor (Float (Src_H) * Scale)));
               Tile : Rgba_Buffer_Access :=
                 new Rgba_Buffer (0 .. Dst_W * Dst_H * 4 - 1);
            begin
               Tile.all := [others => 0];

               --  Average every source pixel the destination pixel covers. This
               --  is a reduction of six times or more from an emoji strike, and
               --  picking one source pixel out of forty would turn a face into
               --  confetti.
               for Row in 0 .. Dst_H - 1 loop
                  for Col in 0 .. Dst_W - 1 loop
                     declare
                        Y0 : constant Natural := Row * Src_H / Dst_H;
                        Y1 : constant Natural :=
                          Natural'Max (Y0 + 1, (Row + 1) * Src_H / Dst_H);
                        X0 : constant Natural := Col * Src_W / Dst_W;
                        X1 : constant Natural :=
                          Natural'Max (X0 + 1, (Col + 1) * Src_W / Dst_W);

                        Sum_R, Sum_G, Sum_B, Sum_A : Natural := 0;
                        Count : Natural := 0;
                     begin
                        for Sy in Y0 .. Y1 - 1 loop
                           for Sx in X0 .. X1 - 1 loop
                              declare
                                 At_Src : constant Natural := (Sy * Src_W + Sx) * 4;
                              begin
                                 exit when At_Src + 3 > Src'Last;
                                 Sum_R := Sum_R + Natural (Src (At_Src));
                                 Sum_G := Sum_G + Natural (Src (At_Src + 1));
                                 Sum_B := Sum_B + Natural (Src (At_Src + 2));
                                 Sum_A := Sum_A + Natural (Src (At_Src + 3));
                                 Count := Count + 1;
                              end;
                           end loop;
                        end loop;

                        if Count > 0 then
                           declare
                              At_Dst : constant Natural := (Row * Dst_W + Col) * 4;
                           begin
                              Tile (At_Dst) := Alpha (Sum_R / Count);
                              Tile (At_Dst + 1) := Alpha (Sum_G / Count);
                              Tile (At_Dst + 2) := Alpha (Sum_B / Count);
                              Tile (At_Dst + 3) := Alpha (Sum_A / Count);
                           end;
                        end if;
                     end;
                  end loop;
               end loop;

               G :=
                 (Width => Dst_W, Height => Dst_H,
                  Advance_X => Float (Box_W),
                  --  Sit the picture inside the line rather than on the baseline:
                  --  an emoji has no baseline of its own, and centring it in the
                  --  cell is what puts it level with the text beside it.
                  Bearing_Y =>
                    Ascent (R) - Float ((R.State.Cell_Height_V - Dst_H) / 2),
                  others => <>);

               if not Commit_Colour_Tile (R, C, Tile, G) then
                  return Atlas_Full;
               end if;

               return Success;
            end;
         end;
      end;
   exception
      when others =>
         return Glyph_Missing;
   end Get_Colour_Glyph;

   function Colour_Sheet_Width (R : Renderer) return Natural is
     (if R.State = null then 0 else R.State.Colour_Width);

   function Colour_Sheet_Height (R : Renderer) return Natural is
     (if R.State = null then 0 else R.State.Colour_Height);

   function Colour_Sheet_Pixels (R : Renderer) return access constant Rgba_Buffer is
   begin
      if R.State = null then
         return null;
      end if;

      return R.State.Colour_Sheet;
   end Colour_Sheet_Pixels;

   function Colour_Sheet_Dirty (R : Renderer) return Boolean is
     (R.State /= null and then R.State.Colour_Dirty_V);

   procedure Clear_Colour_Sheet_Dirty (R : in out Renderer) is
   begin
      if R.State /= null then
         R.State.Colour_Dirty_V := False;
      end if;
   end Clear_Colour_Sheet_Dirty;

end Textrender;
