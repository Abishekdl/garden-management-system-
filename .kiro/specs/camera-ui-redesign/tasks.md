# Camera UI Redesign Implementation Plan

- [x] 1. Remove existing complex overlay controls and simplify camera preview structure


  - Remove the right-side filter control indicators from the build method
  - Remove the left-side zoom control indicators from the build method
  - Clean up the existing Stack layers to prepare for new simplified structure
  - _Requirements: 7.1, 7.2, 1.1, 1.2_



- [ ] 2. Implement new layered UI structure with proper positioning
  - Restructure the main Stack widget to use the new 4-layer approach (Base, Filter, Control, Navigation)
  - Position the full-screen camera preview as the base layer


  - Ensure filter overlay maintains proper transparency and positioning
  - _Requirements: 1.1, 1.3, 8.1_

- [ ] 3. Create simplified top controls with mute button
  - Implement the top-left mute/unmute button with circular design and semi-transparent background


  - Apply consistent styling with 48px diameter, opacity 0.35, and white icons
  - Position button at 36px from top and 16px from left
  - Add subtle shadow effects for depth perception
  - _Requirements: 2.1, 2.2, 2.3, 8.2, 8.3, 8.4_



- [ ] 4. Redesign center capture button with new specifications
  - Update the main capture button to use 80px diameter with transparent background and white border
  - Implement inner white circle (65px diameter) design
  - Ensure recording state changes button to red with timer display
  - Position button centered horizontally at 100px from bottom


  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5_

- [ ] 5. Implement side control buttons for history and camera switching
  - Create left-side history button (56px diameter) positioned 40px from left edge
  - Create right-side camera switch button (56px diameter) positioned 40px from right edge


  - Apply consistent circular design with semi-transparent backgrounds (opacity 0.35)
  - Ensure proper alignment with the main capture button
  - _Requirements: 4.1, 4.2, 4.3, 4.4, 4.5_

- [x] 6. Add instruction text with proper styling and positioning


  - Implement "Tap for photo, hold for video" text with semi-transparent background
  - Position text centered horizontally at 170px from bottom
  - Apply rounded corners (20px radius) and proper padding (16px horizontal, 8px vertical)
  - Use white text with 14px font size and shadow effects
  - _Requirements: 6.1, 6.2, 6.3, 6.4_



- [ ] 7. Update bottom navigation bar design
  - Modify existing bottom navigation to use gradient background (black to transparent)
  - Ensure 80px height and proper spacing for navigation items
  - Update navigation buttons to use circular design with consistent styling
  - Maintain Camera tab as active state with proper highlighting



  - _Requirements: 5.1, 5.2, 5.3, 5.4_

- [ ] 8. Apply consistent visual design system across all components
  - Ensure all circular buttons use consistent design patterns
  - Apply semi-transparent black backgrounds with 0.35 opacity to all control elements
  - Standardize white icons with consistent sizing across all buttons
  - Implement consistent shadow effects for depth perception on all floating elements
  - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_

- [ ] 9. Test and verify functionality preservation
  - Verify all photo capture functionality works with new UI layout
  - Test video recording capabilities including hold gesture and recording state display
  - Validate location services integration remains functional
  - Confirm upload and history features work correctly with new navigation
  - Test camera switching and mute/unmute functionality
  - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6_

- [ ] 10. Optimize performance and conduct final testing
  - Test UI responsiveness across different screen sizes and orientations
  - Verify smooth transitions between different camera states (idle, recording, uploading)
  - Validate gesture controls work properly (tap, hold, navigation)
  - Ensure consistent visual appearance matches design specifications
  - Test memory usage and performance with new UI structure
  - _Requirements: 1.4, 8.5, 9.1, 9.2, 9.3, 9.4, 9.5, 9.6_