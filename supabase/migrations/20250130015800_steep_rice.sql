/*
  # Configuração Inicial do Banco de Dados

  1. Extensões
    - uuid-ossp: Para geração de UUIDs
    - storage: Para armazenamento de arquivos
    - pg_cron: Para agendamento de tarefas

  2. Tabelas Principais
    - pillars: Armazena os pilares do diagnóstico
    - questions: Armazena as questões relacionadas aos pilares
    - diagnostic_results: Armazena os resultados dos diagnósticos
    - settings: Armazena configurações do sistema

  3. Segurança
    - Row Level Security (RLS) em todas as tabelas
    - Políticas de acesso específicas por tabela
    - Restrições e validações de dados

  4. Otimizações
    - Índices para melhor performance
    - Triggers para atualização automática de timestamps
*/

-- Habilitar Extensões Necessárias
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "storage";
CREATE EXTENSION IF NOT EXISTS "pg_cron";

-- Função de Atualização de Timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ language 'plpgsql';

-- Tabela de Pilares
CREATE TABLE pillars (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  name text NOT NULL,
  "order" integer NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX idx_pillars_order ON pillars ("order");

-- Tabela de Questões
CREATE TABLE questions (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  pillar_id uuid NOT NULL,
  text text NOT NULL,
  points integer NOT NULL DEFAULT 1,
  positive_answer text NOT NULL CHECK (positive_answer IN ('SIM', 'NÃO')),
  answer_type text NOT NULL CHECK (answer_type IN ('BINARY', 'TERNARY')),
  "order" integer NOT NULL,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  CONSTRAINT fk_pillar
    FOREIGN KEY (pillar_id)
    REFERENCES pillars(id)
    ON DELETE CASCADE
);

CREATE INDEX idx_questions_pillar_id ON questions (pillar_id);
CREATE INDEX idx_questions_order ON questions ("order");

-- Tabela de Resultados de Diagnóstico
CREATE TABLE diagnostic_results (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id uuid NOT NULL,
  company_data jsonb NOT NULL,
  answers jsonb NOT NULL,
  pillar_scores jsonb NOT NULL,
  total_score numeric NOT NULL,
  max_possible_score numeric NOT NULL,
  percentage_score numeric NOT NULL,
  created_at timestamptz DEFAULT now(),
  CONSTRAINT fk_user
    FOREIGN KEY (user_id)
    REFERENCES auth.users(id)
    ON DELETE CASCADE
);

CREATE INDEX idx_diagnostic_results_user_id ON diagnostic_results(user_id);
CREATE INDEX idx_diagnostic_results_created_at ON diagnostic_results(created_at DESC);

-- Tabela de Configurações
CREATE TABLE settings (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  logo text,
  navbar_logo text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

-- Configuração do Storage
INSERT INTO storage.buckets (id, name, public)
VALUES ('logos', 'logos', true)
ON CONFLICT (id) DO NOTHING;

-- Habilitar RLS em Todas as Tabelas
ALTER TABLE pillars ENABLE ROW LEVEL SECURITY;
ALTER TABLE questions ENABLE ROW LEVEL SECURITY;
ALTER TABLE diagnostic_results ENABLE ROW LEVEL SECURITY;
ALTER TABLE settings ENABLE ROW LEVEL SECURITY;

-- Políticas de Segurança para Pilares
CREATE POLICY "Pillars are viewable by everyone"
  ON pillars FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Pillars are insertable by authenticated users"
  ON pillars FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Pillars are updatable by authenticated users"
  ON pillars FOR UPDATE
  TO authenticated
  USING (true);

-- Políticas de Segurança para Questões
CREATE POLICY "Questions are viewable by everyone"
  ON questions FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Questions are insertable by authenticated users"
  ON questions FOR INSERT
  TO authenticated
  WITH CHECK (true);

CREATE POLICY "Questions are updatable by authenticated users"
  ON questions FOR UPDATE
  TO authenticated
  USING (true);

-- Políticas de Segurança para Resultados de Diagnóstico
CREATE POLICY "Enable read access for users based on user_id"
  ON diagnostic_results FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Enable insert for authenticated users only"
  ON diagnostic_results FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Enable delete for users based on user_id"
  ON diagnostic_results FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);

-- Políticas de Segurança para Configurações
CREATE POLICY "Settings are viewable by everyone"
  ON settings FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Settings are updatable by authenticated users"
  ON settings FOR UPDATE
  TO authenticated
  USING (true);

-- Políticas de Storage
CREATE POLICY "Usuários autenticados podem fazer upload de logos"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'logos' AND
    (storage.foldername(name))[1] = 'logos'
  );

CREATE POLICY "Logos são publicamente visíveis"
  ON storage.objects FOR SELECT
  TO public
  USING (bucket_id = 'logos');

CREATE POLICY "Usuários autenticados podem deletar logos"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'logos');

-- Triggers para Atualização de Timestamps
CREATE TRIGGER update_pillars_updated_at
  BEFORE UPDATE ON pillars
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_questions_updated_at
  BEFORE UPDATE ON questions
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_settings_updated_at
  BEFORE UPDATE ON settings
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Função e Agendamento de Heartbeat
CREATE OR REPLACE FUNCTION public.fn_heartbeat()
RETURNS void AS $$
BEGIN
  PERFORM 1;
END;
$$ LANGUAGE plpgsql;

SELECT cron.schedule(
  'heartbeat-job',
  '30 0 * * *',
  'SELECT public.fn_heartbeat();'
);

-- Inserir Configuração Inicial
INSERT INTO settings (id)
VALUES ('00000000-0000-0000-0000-000000000000')
ON CONFLICT (id) DO NOTHING;