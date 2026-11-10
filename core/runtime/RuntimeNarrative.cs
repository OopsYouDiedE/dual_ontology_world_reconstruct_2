using System.Text.Json;

namespace DuelView.Runtime;

public sealed record ActionNarrative(string Kind,string Speaker,string SpeakerLabel,string Text,string[] Recipients,string EvidenceId="");

/// <summary>Records authored presentation at the successful action boundary.
/// Hearing an utterance records that it was said, not that its assertions are true.</summary>
public sealed partial class RuntimeSession
{
    private ActionNarrative[] CompleteNarrative(Decision decision)
    {
        var declaration=decision.Action.Declaration;
        var speaker=actors[decision.Actor];
        var lines=new List<ActionNarrative>();
        var privateText=declaration.Get("completion_text").Text();
        if(privateText.Length>0)lines.Add(new("reflection",speaker.Id,speaker.Declaration.Get("name").Text(speaker.Id),privateText,[speaker.Id]));
        foreach(var line in declaration.Get("completion_lines").Items())
        {
            Func<FieldKey,Fact?> read=World.Read;
            var viewpoint=line.Get("speaker").Text();
            if(viewpoint.Length>0)read=actors[viewpoint].Recall;
            if(line.Get("when").ValueKind==JsonValueKind.Object&&Condition.Compile(line.Get("when"),speaker.Id).Evaluate(read)!=Truth.True)continue;
            lines.Add(new("reflection",speaker.Id,speaker.Declaration.Get("name").Text(speaker.Id),line.Get("text").Text(),[speaker.Id]));
        }
        var publicText=declaration.Get("public_completion_text").Text();
        if(publicText.Length==0)return lines.ToArray();
        var room=World.Read(new(speaker.Id,"state","room"))?.Value.Text()??"";
        var audience=actors.Values.Where(actor=>actor.Id==speaker.Id||room.Length>0&&
            World.Read(new(actor.Id,"state","room"))?.Value.Text()==room&&
            World.Read(new(actor.Id,"phys","asleep")) is {Known:true,Conflicted:false} awake&&awake.Value.ValueKind==JsonValueKind.False&&!Incapacitated(actor.Id))
            .Select(actor=>actor.Id).ToArray();
        var hidden=speaker.Declaration.Get("hidden").Flag();
        var publicName=speaker.Declaration.Get("public_name").Text();
        var label=publicName.Length>0?publicName:hidden?"看不见的说话者":speaker.Declaration.Get("name").Text("在场者");
        var identity=hidden&&publicName.Length==0?"":speaker.Id;
        var evidenceId="utterance/"+(++nextEvidence);
        var key=new FieldKey("utterance:"+decision.Execution,"doc","text");
        var value=JsonSerializer.SerializeToElement(publicText);
        lines.Add(new("speech",identity,label,publicText,audience,evidenceId));
        foreach(var recipient in audience)
        {
            var source=JsonSerializer.SerializeToElement(new {actor=recipient==speaker.Id?speaker.Id:identity,speaker_label=label,recipient,
                action=decision.Action.Id,execution=decision.Execution,method="spoken",channel="hearing",heard_in=room,scope="same_room",utterance_id=evidenceId});
            actors[recipient].ReceiveDirected(new(evidenceId,key,value,1,ContentTime,InformationOrigin.Communication,source));
        }
        return lines.ToArray();
    }
}
