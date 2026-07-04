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

   package Glyph_Caches is new Ada.Containers.Hashed_Maps
     (Key_Type        => Codepoint,
      Element_Type    => Cached_Glyph,
      Hash            => Codepoint_Hash,
      Equivalent_Keys => "=");

   Glyph_Padding : constant Natural := 1;

   use type Textrender.Fonts.Glyph_Lookup_Result;

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

   type Renderer_State is record
      Font          : Textrender.Fonts.Font;
      Fallbacks     : Font_Vectors.Vector;
      Atlas         : Textrender.Atlases.Atlas;
      Cache         : Glyph_Caches.Map;
      Italic_Cache  : Glyph_Caches.Map;
      Pixel_Size    : Positive := 1;
      Cell_Width_V  : Positive := 1;
      Cell_Height_V : Positive := 1;
      Atlas_Dirty_V : Boolean := False;
   end record;

   procedure Reset_Fallbacks (State : in out Renderer_State);

   procedure Reset_Fallbacks (State : in out Renderer_State) is
   begin
      for F of State.Fallbacks loop
         Textrender.Fonts.Reset (F);
      end loop;

      State.Fallbacks.Clear;
   end Reset_Fallbacks;

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
   -- Initialize / Finalize
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
         Free_State (R.State);
      end if;
   end Finalize;

   -----------------------------
   -- Reset
   -----------------------------

   procedure Reset (R : in out Renderer) is
   begin
      Ensure_State (R);

      Textrender.Fonts.Reset (R.State.Font);
      Reset_Fallbacks (R.State.all);
      Textrender.Atlases.Reset (R.State.Atlas);

      R.State.Cache.Clear;
      R.State.Italic_Cache.Clear;

      R.State.Pixel_Size    := 1;
      R.State.Cell_Width_V  := 1;
      R.State.Cell_Height_V := 1;

      R.State.Atlas_Dirty_V := False;
   end Reset;

   -----------------------------
   -- Load_Font
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
   -- Add_Fallback_Font
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
   -- Metrics
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
   -- Get_Glyph
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

      function Cache_Contains (Key : Codepoint) return Boolean is
        (case Style is
           when Regular => R.State.Cache.Contains (Key),
           when Italic  => R.State.Italic_Cache.Contains (Key));

      function Cache_Element (Key : Codepoint) return Cached_Glyph is
        (case Style is
           when Regular => R.State.Cache.Element (Key),
           when Italic  => R.State.Italic_Cache.Element (Key));
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

      if Cache_Contains (C) then
         declare
            Cached : constant Cached_Glyph := Cache_Element (C);
         begin
            M := Cached.Metric;
            return Cached.Status;
         end;
      end if;

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

      if not Textrender.Fonts.Has_Glyph (R.State.Font, C) then
         for F of R.State.Fallbacks loop
            if Textrender.Fonts.Has_Glyph (F, C) then
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
   -- Atlas Access
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
   -- Preload
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

end Textrender;
