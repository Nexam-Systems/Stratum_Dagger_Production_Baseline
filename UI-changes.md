# UI Changes to make as per the slide numbers

## KAN-28: adaptive settings and tool navigation

The dark concept in issue #64 is the visual target (including its colors), per
the subsequent design clarification. Styling is scoped to the settings/tool
components; High Contrast still uses the application's accessible palette.

- Dark navy panels, cyan icon tabs and section headings, muted descriptions,
  numbered General sections 01-05, and a full-width Application panel.
- Field labels/descriptions stay together; editors align on the right and stack
  beneath their labels when space is limited. Existing Fact controls retain
  validation, units, persisted values, and callbacks.
- The shared header retains the page selector, with NX/STRATUM branding and
  outlined Reset / cyan Save actions. Search remains available beside the page
  title. General keeps the extra preferences/units wherever previously visible.
- CMake tracks settings templates and shared renderers as generation dependencies.

- Generated application settings pages use two equal-width columns when there
  is room for two 55-character-wide panels plus the gutter; otherwise one column.
  The breakpoint scales with the UI font size. Pages scroll vertically.
- Settings cards are collapsible and initially expanded. Collapsing keeps the
  controls alive and preserves their values. Embedded editors (links, maps,
  telemetry, etc.) span both columns; standalone custom pages retain their layout.
- General separates Operational Limits, User Interface, Position Streaming,
  Audio, and Application, while retaining Vehicle Preferences and Units wherever
  they were previously visible. Fact bindings, defaults and units are unchanged.
- Application Settings, Analyze, and Vehicle Configuration share horizontally
  scrollable tabs. Vehicle section tabs retain completion indicators, search,
  prerequisites and focused-component navigation; Analyze popouts are unchanged.
- The tool-selector button, page title, connection state and page actions share
  one header. Save/Reset appear only for Application Settings, not vehicle
  parameters. Reset remains confirmed and deferred until the next start.
- Check wide/narrow windows, increased UI scaling, both themes, dev/client page
  visibility, keyboard tab scrolling, collapse/expand, and vehicle disconnection.
  Regression coverage: settings generator tests and
  `TopLevelViewsTest::_testResponsiveSettings`.
- Shared tabs must import `QGroundControl` for the C++ palette type, not only
  `QGroundControl.Controls`. `TopLevelViewsTest::_testToolTabButtonLoads` checks
  the real module/resource registration. Tool-page load errors are logged and
  displayed in the main window rather than leaving a blank page.

## Slide-2
The greenbox title “QGroundControl Daily” should be “STRATUM with version number. 

## Slide-3
1. The define AOP, Takeoff, return to base and land must be like buttons. And shoudl match the accent color we have right now. 
2. When user presses takeoff, a new pop up should appear which should ask user for takeoff altitude and caution that pressing ok will launch the vehicle to desired altitude. 
3. There is a built in feature in qgroundcontrol where whenever a new flight mode is swithced, a bar appears on top which user has to long press. I want that bar to be placed in the bottom. it is ergonomically more convenient. 

## slide-4
1. during vehicle in flight, upon left click we get a menu like go to location, orbit at location, ROI at location etc. I want them all gone. 
2. instead I want an option called "Standoff here". When a user presses this, a pop should appear asking for standoff distance, standoff height, standoff angle. 
3. standoff distance means how far away from the standoff target the vehicle should be. standoff height is how high. standoff direction/angle is from which direction the vehicle should face the standoff target. 
4. when the vehicle reaches the standoff point, stratum should ask continue to orbit around standoff target? if you look closely these are basically same params as orbit but in a different sense. Standoff distance, ehight, direction all make paramsters for orbit. 

## Slide-5
1. A new button called Engage. It will invoke a flight mode present in PX4. Just place the button for now without any functions. accent should match.


It should be known that all UI changes above should also hold true when video to map and vice versa is switched. 
