Arduino MIDI Controller

# Specs

* Based on Custom Audio Engineering RS5

* Each preset holds 10 MIDI Control messages. Each Bank holds 5 presets. 30 banks available.
* Selectable between Direct Mode (Sends midi messages) and Preset Mode (Sends groups of 10 midi messages associated to each direct)

* Buttons numbered from 0-9. In Direct mode, each one is a Midi Message. In Preset Mode, buttons 1-5 are Direct and buttons 6-0 are mapped to presets 1-5 (Button 6 = Preset 1, Button 7 = Preset 2, etc).
* When in Direct Mode, buttons 0-9 send MIDI Control Messages On(127) or Off(0)
* Each button has a led. In Direct Mode, the led displays if each Control is currently On (127) or Off(0). In Preset mode, leds associated to buttons 1-5 shows if it's control is On or Off. Leds associated to buttons 6-0 (Presets 1-5) displays which Preset is currently on. In bank select mode, all Preset leds are off. The Direct leds shows it's current status.


* If the current preset has been changed (any direct), the dot in the display blinks.

* When in Bank select mode, display blinks until a preset in that bank is selected.

* Display shows current bank number when in Preset mode. In Direct Mode, shows "Dir". In Bank select mode, shows the bank to be choosen (needs to confirm selection choosing a Preset)

* When in Preset Mode, buttons 1-5 send MIDI Control Messages On(127) or Off(0) like Direct Mode and buttons 6-0 send presets associated to the current Bank.
* Directs 0-9 mapped to Midi Control Messages 80-89.
* Up button - Selects Bank Up in Preset Mode. In Direct Mode, resets any changes to current preset and reloads it.
* Down button - Selects Bank Up in Preset Mode. In Direct Mode, saves any changes to current preset.
* Dir/Edit button - Switches between Direct and Preset mode. In temporary bank select mode, resets current changes and reloads current preset.
* Led Display - Shows


* Saves/recalls last used bank and preset when turned off.

# Manual

When turned on, controller starts in Preset mode. The last used Bank and Preset are recalled. The controller shows the current bank number in the display and the preset led lit.

User can choose Preset 1-5 in that bank. Choosing it, the controller sends the 10 MIDI Control Messages associated to the 10 direct access buttons. The top buttons are always direct access switches and the leds show its current status (On/Off).

Bank Up/Bank Down, allows user to choose another bank, the display starts flashing and shows the destination bank. To confirm the bank choice, user must choose one


# Todo

[X] Ao ligar, definir banco padrão ou carregar da memoria ultimo banco usado
[X] Atualizar display
[X] - Definir se é carregado ou não um Preset ao ligar
[X] Caso seja carregado um preset, enviar comandos MIDI, atualizar leds
[X] Ao entrar no modo direct (troca de mode), ler banco atual e atualizar leds para todas os switches (criar função para atualizar leds).
[X] Ao voltar para modo Preset, atualizar Leds de switches e acender o do preset atual.
[X] Verificar função de impressao e conversao dos numeros no display. Verificar exemplo em: http://www.arduino.cc/playground/Main/LedControl
[X] Ao trocar de Preset, enviar comandos MIDI, atualizar Leds, salvar na memoria de ultimo preset selecionado.
[X] Ao trocar de banco, o preset atualmente em uso (status dos switches) nao deve ser trocado, apenas é alterado ao selecionar um dos presets (1-5). Numero fica piscando até que um preset seja escolhido. Leds de presets nos switches ficam apagados. Salvar na memoria de ultimo banco selecionado.
[X]No modo de selecao de banco, qualquer switch exceto os de preset retornam para o modo de preset.
[X]Modo de selecao de banco, ao apertar um dos direct switches (1-5), o que fazer?
[X] Criar limite de bancos com rollover (98 -> 99 -> 00).
[X] Ao segurar o botao bank up/down, o banco muda mais rapidamente.
[X] Apos alterar um preset no direct mode, o ponto do ultimo digito fica piscando até ser salvo
[X] Em Direct Mode, para salvar a nova configuracao no preset atual, pressionar o botao BankDown. Retorna para modo preset. Led de ponto para de piscar
[X] Em Direct Mode, para desfazer a nova configuracao no preset atual, pressionar o botao BankUp. Led de ponto para de piscar
[X] Gravar na memoria canal MIDI usado e carregar na inicializacao.
[ ] Adicionar mensagens de debug para novos casos
[ ] Criar menu de configuracoes.
[ ] Canal MIDI
[ ] Control Numbers enviados
[ ] ...

[ ] Criar logica para pedal analogico (expression)

--------------------------------------------------------------------
Conexao do Led Driver ao display e leds:

Pinos de Dig0, Dig1 e Dig2 devem ser conectados aos 3 digitos do display
Pinos 0,1,2,3,4,5,6,7 do Dig3 e pinos 0,1 do Dig4 devem ser conectados nos leds 0,1,2,3,4,5,6,7,8,9 respectivamente.
