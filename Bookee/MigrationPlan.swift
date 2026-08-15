//
//  MigrationPlan.swift
//  K Test
//
//  Created by Kara Eveland on 2/17/26.
//

import Foundation
import SwiftData

// MARK: - Migration Guidelines

/*
 ## When You Need to Change the Item Model

 ### 1. SIMPLE CHANGES (Auto-migrated by SwiftData):

 ✅ **Adding Optional Properties:**
 ```swift
 var newProperty: String? = nil  // Safe - auto-migrated
 ```

 ✅ **Adding Properties with Defaults:**
 ```swift
 var newProperty: String = "default"  // Safe - auto-migrated
 ```

 ✅ **Renaming Properties:**
 ```swift
 @Attribute(.originalName("oldName"))
 var newName: String  // Safe - tells SwiftData the old name
 ```

 ### 2. COMPLEX CHANGES (Require Manual Migration):

 ⚠️ **Removing Properties:**
 - Must create migration to handle existing data

 ⚠️ **Changing Property Types:**
 - Example: String → Int, Date → String, etc.
 - Must create migration to transform data

 ⚠️ **Adding Non-Optional Properties:**
 - Without defaults requires migration to provide values

 ⚠️ **Changing Relationships:**
 - Adding/removing relationships between models

 ### 3. HOW TO IMPLEMENT MANUAL MIGRATION:

 **Step 1:** Create a SchemaMigrationPlan:
 ```swift
 enum BookeeMigrationPlan: SchemaMigrationPlan {
     static var schemas: [any VersionedSchema.Type] {
         [SchemaV1.self, SchemaV2.self]
     }
     static var stages: [MigrationStage] {
         [
             MigrationStage.custom(
                 fromVersion: SchemaV1.self,
                 toVersion: SchemaV2.self,
                 willMigrate: nil,
                 didMigrate: { context in
                     // Perform data transformation here
                 }
             )
         ]
     }
 }
 ```

 **Step 2:** Create versioned schemas:
 ```swift
 enum SchemaV1: VersionedSchema {
     static var versionIdentifier = Schema.Version(1, 0, 0)
     static var models: [any PersistentModel.Type] { [ItemV1.self] }
 }

 enum SchemaV2: VersionedSchema {
     static var versionIdentifier = Schema.Version(2, 0, 0)
     static var models: [any PersistentModel.Type] { [ItemV2.self] }
 }
 ```

 **Step 3:** Create model versions:
 ```swift
 @Model
 final class ItemV1 {
     // Old model structure
 }

 @Model
 final class ItemV2 {
     // New model structure
 }
 ```

 **Step 4:** Wire up the plan in BookeeApp.swift:
 ```swift
 let container = try ModelContainer(
     for: Item.self,
     migrationPlan: BookeeMigrationPlan.self,
     configurations: [modelConfiguration]
 )
 ```

 ### 4. TESTING MIGRATIONS:

 **Before Release:**
 - Keep a device/simulator with old version installed
 - Add test data in the old version
 - Install the new version WITHOUT deleting the app
 - Verify all data is preserved and correctly migrated
 - Check console logs for migration messages

 **Debug Migration Issues:**
 - Enable verbose logging in migration stages
 - Test with various data scenarios (empty, full, edge cases)
 - Keep backups of test databases

 ### 5. IMPORTANT NOTES FOR YOUR APP:

 **Current External Storage Properties:**
 - `expensesData`: [Expense] encoded as JSON
 - `incomesData`: [Income] encoded as JSON

 If you change the Expense/Income structs:
 - Ensure they remain Codable
 - Add new properties as optional or with defaults
 - Or create migration to re-encode with new structure

 **Example: Adding property to Expense:**
 ```swift
 struct Expense: Codable {
     // Existing properties...
     var newProperty: String? = nil  // ✅ Safe - optional with default
 }
 ```

 **Example: Changing Expense property type:**
 ```swift
 // ⚠️ BREAKING CHANGE - Requires migration
 struct Expense: Codable {
     var amount: String  // Was Double - THIS BREAKS EXISTING DATA
 }
 ```

 Solution:
 1. Keep old struct as ExpenseV1
 2. Create new struct as ExpenseV2
 3. In migration, decode old data, transform, encode new data

 ### 6. FOR DEVELOPMENT ONLY:

 If you want to start fresh without migration during development:
 - Delete the app from simulator/device
 - Or use `isStoredInMemoryOnly: true` in ModelConfiguration
 - ⚠️ NEVER ship with in-memory storage!

 ### 7. VERSIONING STRATEGY:

 Document each version with:
 - What changed
 - Why it changed
 - Migration strategy used

 Example:
 ```
 Version 1.0: Initial release
 Version 1.1: Added targetYear property (auto-migrated, optional)
 Version 1.2: Added deletedDate for soft delete (auto-migrated, optional)
 Version 2.0: [Planned] Add Category model (requires manual migration)
 ```

 ### 8. EMERGENCY RECOVERY:

 The app includes automatic recovery in BookeeApp.swift:
 - Attempts to create ModelContainer
 - On failure, tries to remove corrupted store files
 - Creates fresh container
 - Falls back to in-memory if all else fails

 This prevents app crashes but user loses data.
 Consider adding data export/import for user recovery.
 */
