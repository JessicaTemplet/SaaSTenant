# Same pattern as the RLS policy on users (see
# 20260818000005_enable_row_level_security_on_users.rb) — copied per
# table, on purpose, per the note in that migration and in the project
# README: RLS is table-owned, not something that just cascades.
class EnableRowLevelSecurityOnDocumentsAndDocumentOps < ActiveRecord::Migration[8.1]
  def change
    execute("ALTER TABLE documents ENABLE ROW LEVEL SECURITY;\nALTER TABLE documents FORCE ROW LEVEL SECURITY;\n\nCREATE POLICY tenant_isolation ON documents\n  USING (\n    tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::bigint\n    OR current_setting('app.bypass_rls', true) = 'on'\n  );\n")

    execute("ALTER TABLE document_ops ENABLE ROW LEVEL SECURITY;\nALTER TABLE document_ops FORCE ROW LEVEL SECURITY;\n\nCREATE POLICY tenant_isolation ON document_ops\n  USING (\n    tenant_id = NULLIF(current_setting('app.current_tenant_id', true), '')::bigint\n    OR current_setting('app.bypass_rls', true) = 'on'\n  );\n")
  end
end
