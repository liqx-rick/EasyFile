# Instant Rename Update Optimization

## Overview
Optimized the file rename operation in the preview page to provide instant UI updates without visible loading, matching the UX of the favorite toggle feature.

## Problem
Previously, when a user renamed a file from the preview page and returned to the file list:
- **Favorite toggle**: Instant update (direct ViewModel state modification)
- **Rename operation**: Visible loading delay (full list reload via `loadFiles()`)

This inconsistency created a suboptimal user experience.

## Solution
Modified the rename operation to use instant ViewModel update instead of full list reload.

### Changes Made

#### 1. Repository Interface (`lib/data/repositories/file_repository.dart`)
```dart
// Before:
Future<bool> renameFile(FileItem file, String newName);

// After:
Future<FileItem?> renameFile(FileItem file, String newName);
```
Changed return type from `bool` to `FileItem?` to return the updated file data.

#### 2. Repository Implementation (`lib/data/sources/local_file_source.dart`)
- Updated method signature to return `Future<FileItem?>`
- Changed all early return statements from `false` to `null`
- After successful rename, construct and return updated `FileItem`:
```dart
return FileItem(
  path: newPath,
  name: newName,
  isDirectory: file.isDirectory,
  size: file.size,
  modified: file.modified,
);
```

#### 3. Presenter Layer (`lib/presenter/file_presenter.dart`)
```dart
// Before:
final success = await repository.renameFile(file, newName);
if (success) {
  await loadFiles(viewModel.currentPath);  // Full reload
}

// After:
final renamedFile = await repository.renameFile(file, newName);
if (renamedFile != null) {
  viewModel.updateFileInList(file.path, renamedFile);  // Instant update
}
```

#### 4. ViewModel (`lib/viewmodel/file_viewmodel.dart`)
Already had the `updateFileInList()` method added in previous optimization:
```dart
void updateFileInList(String oldPath, FileItem updatedFile) {
  // Update in both _allFiles and _files
  final allIndex = _allFiles.indexWhere((f) => f.path == oldPath);
  if (allIndex != -1) {
    _allFiles[allIndex] = updatedFile;
  }
  
  final index = _files.indexWhere((f) => f.path == oldPath);
  if (index != -1) {
    _files[index] = updatedFile;
    notifyListeners();  // Trigger instant UI update
  }
}
```

## Benefits
1. **Instant Feedback**: File name updates immediately without visible loading
2. **Consistent UX**: Matches the instant update behavior of favorite toggle
3. **Better Performance**: Avoids unnecessary full list reload from file system
4. **Improved Perceived Performance**: Users see changes immediately

## Technical Details
- The solution maintains the same safety checks (PathSecurity validation)
- All error conditions return `null` instead of throwing exceptions
- The file system rename operation itself remains unchanged
- Only the post-rename update mechanism was optimized

## Testing Recommendations
1. Rename file in preview page
2. Press back button
3. Verify file name updates instantly without loading indicator
4. Test with different file types (documents, images, videos)
5. Test rename failures (permission denied, invalid name) still show proper error messages

## Related Optimizations
This pattern can be applied to other operations:
- **Move operation**: Could use `updateFileInList()` to update path
- **Delete operation**: Could use `removeFileFromList()` for instant removal
- **Copy operation**: Doesn't need optimization (creates file elsewhere)
