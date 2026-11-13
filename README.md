# PianoSong

App Android para aprender piano no estilo Guitar Hero. As notas caem na tela (celular na horizontal) e você toca no **teclado de verdade**. O app ouve pelo microfone e confere se você acertou.

## Recursos
- **Biblioteca**: busca no [BitMidi](https://bitmidi.com) direto no app, importação de `.mid` do celular e 2 músicas de demonstração (domínio público). Os MIDIs ficam só no celular.
- **Escolher partes**: em MIDIs de banda, você marca qual instrumento vira piano (a bateria é ignorada).
- **4 dificuldades geradas automaticamente** a partir da música original:
  | Nível | Conteúdo | Velocidade |
  |---|---|---|
  | Iniciante | só a melodia da mão direita, simplificada | 50% |
  | Fácil | melodia + baixo da mão esquerda no início dos compassos | 65% |
  | Médio | duas mãos, até 2 notas por mão em cada acorde | 80% |
  | Original | tudo | 100% |
- **Modos**: no tempo, ou **modo espera** (a música para até você acertar). Também dá para treinar **mãos separadas**, fazer **loop de um trecho** (com aceleração a cada volta sem erro) e ajustar a **velocidade** livremente (25% a 120%).
- **Teclado configurável**: 25, 37, 49, 61, 76 ou 88 teclas. Se a música não cabe, ela é transposta ou dobrada por oitava.
- **Pontuação**: Perfeito/Bom/Errou, combo com multiplicador, estrelas (70/85/95%), recordes, histórico com gráfico de evolução e sequência de dias praticando. Cada nível é liberado com 3 estrelas no anterior (ou libere tudo nas configurações).
- **Nome das notas**: Dó Ré Mi, C D E ou nenhum.

## Como o app ouve o teclado
Ele não tenta transcrever o áudio do zero. Como sabe quais notas **deveriam** soar naquele momento, ele confere a energia dessas notas e dos harmônicos delas no espectro (FFT de 4096 pontos a cada ~23 ms). Uma nota só conta no **ataque**, então segurar uma tecla não conta várias vezes. Notas erradas também são detectadas, mas só aparecem em vermelho e não tiram pontos.

A **calibração** (no primeiro uso) mede o ruído do ambiente, testa 3 notas e mede o atraso do microfone tocando junto com uma luz. O **afinador** (ícone de onda na tela inicial) mostra em tempo real o que o microfone está ouvindo. Use-o se o app não reconhecer alguma nota.

Dicas: deixe o celular perto do teclado, num ambiente silencioso, e não toque outro som no celular durante o jogo.

## Desenvolvimento

Requisitos: [Flutter](https://docs.flutter.dev/get-started/install) (testado com 3.50 / Dart 3.14) e o Android SDK (via Android Studio).

```bash
flutter pub get
flutter test                 # testes unitários
flutter run                  # celular Android conectado por USB (depuração USB ligada)
flutter build apk --release  # gera build/app/outputs/flutter-apk/app-release.apk
```

Teste com a internet (busca e importa MIDIs reais do BitMidi):
```bash
flutter test test/bitmidi_live_test.dart --dart-define=LIVE=true
```

### Estrutura
```
lib/
  core/       notas (nomes, frequências) e geometria do teclado
  song/       leitor de MIDI, importador, divisão de mãos, ajuste ao teclado, gerador de dificuldades
  detection/  FFT, analisador de notas, detector de ataque, escuta do microfone
  game/       motor do jogo (relógio, modo espera, loop), pontuação, desenho das notas caindo
  library/    API do BitMidi, músicas de demonstração, biblioteca/histórico no aparelho
  services/   configurações
  ui/         telas
```
