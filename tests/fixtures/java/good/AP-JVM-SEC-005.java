import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.jsontype.BasicPolymorphicTypeValidator;

public class JsonService {
    // ok: slopguard.jvm.jackson-default-typing
    public ObjectMapper buildMapper() {
        BasicPolymorphicTypeValidator ptv = BasicPolymorphicTypeValidator.builder()
            .allowIfSubType("com.myapp.model.")
            .build();
        return new ObjectMapper().activateDefaultTyping(ptv,
            ObjectMapper.DefaultTyping.NON_FINAL);
    }
}
