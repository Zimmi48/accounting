# Dark Mode Support

This application now includes full dark mode support with theme-aware color palettes.

## Features

- **Light Theme**: Clean, bright interface with light backgrounds
- **Dark Theme**: Eye-friendly dark interface with appropriate contrast
- **Theme-aware colors**: All UI elements adapt to the selected theme

## Theme Detection

The theme is currently set to Light Mode by default. To enable automatic system preference detection, you can:

### Option 1: Manual Toggle (Simple)

The theme is controlled by the `theme` field in the `FrontendModel`. You can toggle between themes by changing the init value in `src/Frontend.elm`:

```elm
, theme = LightTheme  -- or DarkTheme
```

### Option 2: System Preference Detection (Advanced)

For automatic detection of the system's preferred color scheme, you would need to add custom JavaScript. Since this is a Lamdera application, ports are managed differently. Here's what you would need:

1. Create a custom `index.html` wrapper
2. Add JavaScript to detect `prefers-color-scheme`
3. Pass the preference via Lamdera's initialization

Example JavaScript snippet:
```javascript
// Detect system preference
const prefersDark = window.matchMedia && 
                   window.matchMedia('(prefers-color-scheme: dark)').matches;
console.log('System prefers dark mode:', prefersDark);
```

## Color Palettes

### Light Theme
- Background: White (#FFFFFF)
- Surface: White (#FFFFFF) 
- Surface Variant: Light Gray (#E6E6E6)
- Text: Black (#000000)
- Primary: Light Green (#98FB98)
- Error: Light Red (#FF8080)

### Dark Theme
- Background: Very Dark Gray (#121212)
- Surface: Dark Gray (#1E1E1E)
- Surface Variant: Medium Dark Gray (#2D2D2D)
- Text: Light Gray (#E6E6E6)
- Primary: Dark Green (#64C864)
- Error: Dark Red (#C86464)

## Implementation Details

The theme system is implemented using:
- `Theme` type in `Types.elm` (LightTheme | DarkTheme)
- `ColorPalette` record with all theme colors
- Theme-aware color functions in `Frontend.elm`
- All UI elements updated to use the palette

All dialogs, buttons, inputs, and backgrounds now respect the current theme.
